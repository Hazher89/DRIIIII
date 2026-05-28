-- Bilutleie: tidspunkt + automatisk SMS-påminnelse 2 timer før retur.

ALTER TABLE public.vehicle_rentals
  ADD COLUMN IF NOT EXISTS rental_start_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rental_end_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS return_reminder_sent_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_vehicle_rentals_return_reminder
  ON public.vehicle_rentals(company_id, rental_end_at)
  WHERE status = 'approved' AND return_reminder_sent_at IS NULL;

CREATE OR REPLACE FUNCTION public.notify_vehicle_rental_partner_sms(
  p_rental_id UUID,
  p_event TEXT
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  borrower_name TEXT;
  msg TEXT;
  owner_rec RECORD;
  n INT := 0;
  cat TEXT;
  due_label TEXT;
BEGIN
  SELECT
    vr.*,
    p.name AS lender_name,
    p.is_active AS lender_active
  INTO r
  FROM public.vehicle_rentals vr
  JOIN public.partners p ON p.id = vr.lender_partner_id
  WHERE vr.id = p_rental_id;

  IF r IS NULL OR coalesce(r.lender_active, false) = false THEN
    RETURN 0;
  END IF;

  SELECT name INTO borrower_name FROM public.partners WHERE id = r.borrower_partner_id;

  IF r.rental_end_at IS NOT NULL THEN
    due_label := to_char(r.rental_end_at AT TIME ZONE 'Europe/Oslo', 'DD.MM.YYYY HH24:MI');
  ELSIF r.rental_end IS NOT NULL THEN
    due_label := to_char(r.rental_end::timestamp, 'DD.MM.YYYY');
  ELSE
    due_label := 'i henhold til avtalt sluttid';
  END IF;

  msg := CASE p_event
    WHEN 'created' THEN
      'Ny bilutleie i DriftPro: '
      || coalesce(r.unit_code, 'bil')
      || coalesce(' (' || nullif(trim(r.registration_number), '') || ')', '')
      || ' skal leies ut til '
      || coalesce(borrower_name, 'samarbeidspartner')
      || '. Logg inn som bil-eier, les avtalen, ta 6 bilder og send til godkjenning.'
    WHEN 'approved' THEN
      'Bilutleie godkjent av MAVI: '
      || coalesce(r.unit_code, 'bil')
      || coalesce(' (' || nullif(trim(r.registration_number), '') || ')', '')
      || ' er utlevert til '
      || coalesce(borrower_name, 'samarbeidspartner')
      || '. Nøkkel kan overleveres.'
    WHEN 'rejected' THEN
      'Bilutleie avvist av MAVI: '
      || coalesce(r.unit_code, 'bil')
      || coalesce(' (' || nullif(trim(r.registration_number), '') || ')', '')
      || coalesce('. Årsak: ' || nullif(trim(r.rejection_reason), ''), '.')
      || ' Logg inn i DriftPro for detaljer.'
    WHEN 'return_submitted' THEN
      'Retur registrert for '
      || coalesce(r.unit_code, 'bil')
      || coalesce(' (' || nullif(trim(r.registration_number), '') || ')', '')
      || ' fra '
      || coalesce(borrower_name, 'samarbeidspartner')
      || '. MAVI vurderer returen i DriftPro.'
    WHEN 'return_approved' THEN
      'Retur godkjent av MAVI: '
      || coalesce(r.unit_code, 'bil')
      || coalesce(' (' || nullif(trim(r.registration_number), '') || ')', '')
      || ' er tilbake hos utleier og tilgjengelig igjen.'
    WHEN 'return_due_2h' THEN
      'Påminnelse: '
      || coalesce(r.unit_code, 'bil')
      || coalesce(' (' || nullif(trim(r.registration_number), '') || ')', '')
      || ' skal returneres ca. ' || due_label
      || '. Logg inn i DriftPro for retur med bilder, km og drivstoff.'
    ELSE NULL
  END;

  IF msg IS NULL THEN
    RETURN 0;
  END IF;

  cat := CASE p_event
    WHEN 'created' THEN 'vehicle_rental'
    WHEN 'return_due_2h' THEN 'vehicle_rental_return_reminder'
    ELSE 'vehicle_rental_status'
  END;

  FOR owner_rec IN
    SELECT pop.phone FROM public.partner_owner_sms_phones(r.lender_partner_id) pop
  LOOP
    IF owner_rec.phone IS NOT NULL THEN
      PERFORM public.queue_sms(
        r.company_id,
        owner_rec.phone,
        msg,
        cat,
        'vehicle_rentals',
        r.id
      );
      n := n + 1;
    END IF;
  END LOOP;

  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.enqueue_vehicle_rental_return_due_sms()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  n INT := 0;
BEGIN
  FOR r IN
    SELECT vr.id
    FROM public.vehicle_rentals vr
    WHERE vr.status = 'approved'
      AND vr.return_reminder_sent_at IS NULL
      AND vr.rental_end_at IS NOT NULL
      AND vr.rental_end_at <= (now() + interval '2 hours')
      AND vr.rental_end_at > (now() + interval '1 hour 50 minutes')
  LOOP
    PERFORM public.notify_vehicle_rental_partner_sms(r.id, 'return_due_2h');
    UPDATE public.vehicle_rentals
    SET return_reminder_sent_at = now(), updated_at = now()
    WHERE id = r.id;
    n := n + 1;
  END LOOP;

  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.enqueue_vehicle_rental_return_due_sms() TO authenticated, service_role;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      PERFORM cron.unschedule('vehicle-rental-return-reminder');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    PERFORM cron.schedule(
      'vehicle-rental-return-reminder',
      '*/5 * * * *',
      $cron$SELECT public.enqueue_vehicle_rental_return_due_sms();$cron$
    );
  END IF;
END;
$$;
