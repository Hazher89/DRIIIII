-- Bilutleie: send SMS også til låntaker-bedrift ved opprettelse.
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
      'MAVI: Ny bilutleie i DriftPro: '
      || coalesce(r.unit_code, 'bil')
      || coalesce(' (' || nullif(trim(r.registration_number), '') || ')', '')
      || ' skal leies ut til '
      || coalesce(borrower_name, 'samarbeidspartner')
      || '. Logg inn som bil-eier, les avtalen, ta 6 bilder og send til godkjenning.'
    WHEN 'approved' THEN
      'MAVI: Bilutleie godkjent: '
      || coalesce(r.unit_code, 'bil')
      || coalesce(' (' || nullif(trim(r.registration_number), '') || ')', '')
      || ' er utlevert til '
      || coalesce(borrower_name, 'samarbeidspartner')
      || '. Nøkkel kan overleveres.'
    WHEN 'rejected' THEN
      'MAVI: Bilutleie avvist: '
      || coalesce(r.unit_code, 'bil')
      || coalesce(' (' || nullif(trim(r.registration_number), '') || ')', '')
      || coalesce('. Årsak: ' || nullif(trim(r.rejection_reason), ''), '.')
      || ' Logg inn i DriftPro for detaljer.'
    WHEN 'return_submitted' THEN
      'MAVI: Retur registrert for '
      || coalesce(r.unit_code, 'bil')
      || coalesce(' (' || nullif(trim(r.registration_number), '') || ')', '')
      || ' fra '
      || coalesce(borrower_name, 'samarbeidspartner')
      || '. MAVI vurderer returen i DriftPro.'
    WHEN 'return_approved' THEN
      'MAVI: Retur godkjent: '
      || coalesce(r.unit_code, 'bil')
      || coalesce(' (' || nullif(trim(r.registration_number), '') || ')', '')
      || ' er tilbake hos utleier og tilgjengelig igjen.'
    WHEN 'return_due_2h' THEN
      'MAVI: Påminnelse: '
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

  -- Varsle utleier-siden (bileier).
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

  -- Ved opprettelse: varsle også låntaker-bedrift slik at avtalen følges opp.
  IF p_event = 'created' THEN
    FOR owner_rec IN
      SELECT pop.phone FROM public.partner_owner_sms_phones(r.borrower_partner_id) pop
    LOOP
      IF owner_rec.phone IS NOT NULL THEN
        PERFORM public.queue_sms(
          r.company_id,
          owner_rec.phone,
          'MAVI: Ny bilutleie er registrert på deres bedrift i DriftPro. '
          || coalesce(r.unit_code, 'bil')
          || coalesce(' (' || nullif(trim(r.registration_number), '') || ')', '')
          || '. Følg status i Utleie-siden.',
          cat,
          'vehicle_rentals',
          r.id
        );
        n := n + 1;
      END IF;
    END LOOP;
  END IF;

  RETURN n;
END;
$$;
