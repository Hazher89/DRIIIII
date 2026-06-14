-- Ruter publisert uten SMS/e-post (dispatch_status = registered) skal ikke kreve aksept eller purring.

ALTER TABLE public.partner_route_shares
  DROP CONSTRAINT IF EXISTS partner_route_ack_status_check;

ALTER TABLE public.partner_route_shares
  ADD CONSTRAINT partner_route_ack_status_check
  CHECK (ack_status IN ('pending', 'accepted', 'rejected', 'not_required'));

UPDATE public.partner_route_shares
SET
  ack_status = 'not_required',
  ack_at = NULL,
  ack_by = NULL,
  ack_comment = NULL
WHERE dispatch_status = 'registered'
  AND ack_status IN ('pending', 'rejected');

-- Ekstra sikkerhet i automatiske purringer: kun varslede ruter med pending aksept.
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
  route_day DATE;
  today_oslo DATE;
  ch public.notification_channel;
BEGIN
  today_oslo := (timezone('Europe/Oslo', now()))::date;

  FOR rec IN
    SELECT prs.id, prs.company_id, prs.partner_id,
           coalesce(prs.sent_at, prs.created_at) AS dispatched_at,
           p.name AS partner_name, pv.unit_code,
           prs.share_date,
           prs.route_start_at
    FROM public.partner_route_shares prs
    JOIN public.partners p ON p.id = prs.partner_id AND p.is_active = true
    LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
    WHERE prs.ack_status = 'pending'
      AND coalesce(prs.dispatch_status, 'sent') = 'sent'
      AND coalesce(prs.sent_at, prs.created_at) IS NOT NULL
  LOOP
    route_day := greatest(
      rec.share_date,
      (coalesce(rec.route_start_at, rec.share_date::timestamptz) AT TIME ZONE 'Europe/Oslo')::date
    );
    IF route_day < today_oslo THEN
      CONTINUE;
    END IF;

    ch := public.company_partner_notification_channel(
      rec.company_id, 'partner_route_reminder'
    );
    IF ch = 'none'::public.notification_channel THEN
      CONTINUE;
    END IF;

    SELECT coalesce(s.route_ack_reminder_minutes, greatest(s.route_ack_reminder_hours, 1) * 60, 1440)
    INTO mins
    FROM public.company_partner_notification_settings s
    WHERE s.company_id = rec.company_id;
    mins := coalesce(mins, 1440);
    IF mins <= 0 THEN
      CONTINUE;
    END IF;

    base_ts := rec.dispatched_at;
    IF base_ts > now() - (mins || ' minutes')::interval THEN
      CONTINUE;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.sms_outbox o
      WHERE o.reference_id = rec.id
        AND o.category = 'partner_route_reminder'
    ) OR EXISTS (
      SELECT 1 FROM public.email_outbox e
      WHERE e.reference_id = rec.id
        AND e.category = 'partner_route_reminder'
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

COMMENT ON COLUMN public.partner_route_shares.ack_status IS
  'pending/accepted/rejected for varslede ruter (sent). not_required for registered uten varsel.';
