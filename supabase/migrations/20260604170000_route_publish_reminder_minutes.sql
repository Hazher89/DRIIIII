-- Publisering: sent_at, purring i minutter, blokker partner-avvisning.

ALTER TABLE public.partner_route_shares
  ADD COLUMN IF NOT EXISTS sent_at TIMESTAMPTZ;

ALTER TABLE public.company_partner_notification_settings
  ADD COLUMN IF NOT EXISTS route_ack_reminder_minutes INT NOT NULL DEFAULT 1440;

UPDATE public.company_partner_notification_settings
SET route_ack_reminder_minutes = greatest(route_ack_reminder_hours, 1) * 60
WHERE route_ack_reminder_minutes = 1440
  AND route_ack_reminder_hours IS NOT NULL
  AND route_ack_reminder_hours <> 24;

COMMENT ON COLUMN public.company_partner_notification_settings.route_ack_reminder_minutes IS
  'Minutter etter utsendelse før første purring ved manglende aksept';

CREATE OR REPLACE FUNCTION public.enqueue_partner_route_ack_reminders()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  mins INT;
  msg TEXT;
  n INT := 0;
  base_ts TIMESTAMPTZ;
BEGIN
  FOR rec IN
    SELECT prs.id, prs.company_id, prs.partner_id,
           coalesce(prs.sent_at, prs.created_at) AS dispatched_at,
           p.name AS partner_name, pv.unit_code
    FROM public.partner_route_shares prs
    JOIN public.partners p ON p.id = prs.partner_id AND p.is_active = true
    LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
    WHERE coalesce(prs.ack_status, 'pending') = 'pending'
      AND coalesce(prs.dispatch_status, 'sent') = 'sent'
      AND coalesce(prs.sent_at, prs.created_at) IS NOT NULL
  LOOP
    SELECT coalesce(s.route_ack_reminder_minutes, greatest(s.route_ack_reminder_hours, 1) * 60, 1440)
    INTO mins
    FROM public.company_partner_notification_settings s
    WHERE s.company_id = rec.company_id;
    mins := coalesce(mins, 1440);

    base_ts := rec.dispatched_at;
    IF base_ts > now() - (mins || ' minutes')::interval THEN
      CONTINUE;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.sms_outbox o
      WHERE o.reference_id = rec.id
        AND o.category = 'partner_route_reminder'
        AND o.created_at > now() - interval '12 hours'
    ) THEN
      CONTINUE;
    END IF;

    msg := 'PÅMINNELSE: Rute ' || coalesce(rec.unit_code, '') ||
      ' venter på aksept i DriftPro. Logg inn og godkjenn ruten.';

    n := n + public.notify_partner_owner_phones(
      rec.company_id, rec.partner_id, msg, 'partner_route_reminder', 'partner_route_reminder',
      'partner_route_shares', rec.id, 'Purring rute uten aksept'
    );
    n := n + public.notify_partner_owner_emails(
      rec.company_id, rec.partner_id,
      'Påminnelse: rute venter på aksept',
      msg, 'partner_route_reminder', 'partner_route_reminder',
      'partner_route_shares', rec.id, 'Purring rute (e-post)'
    );
  END LOOP;
  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_block_partner_route_reject()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND NEW.ack_status = 'rejected'
     AND coalesce(OLD.ack_status, 'pending') IS DISTINCT FROM 'rejected'
     AND EXISTS (
       SELECT 1 FROM public.profiles p
       WHERE p.id = auth.uid() AND p.partner_id IS NOT NULL
     ) THEN
    RAISE EXCEPTION 'Avvisning er ikke tilgjengelig. Ring kjørekontoret dersom noe ikke stemmer.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_partner_route_reject ON public.partner_route_shares;
CREATE TRIGGER trg_block_partner_route_reject
  BEFORE UPDATE OF ack_status ON public.partner_route_shares
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_block_partner_route_reject();
