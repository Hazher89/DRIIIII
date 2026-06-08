-- Manuell purring: SMS/e-post til partner som ikke har akseptert rute (fra planlegger).

CREATE OR REPLACE FUNCTION public._nudge_partner_route_ack_row(p_share_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  msg TEXT;
  sms_n INT := 0;
  email_n INT := 0;
  ch public.notification_channel;
BEGIN
  SELECT prs.id, prs.company_id, prs.partner_id, pv.unit_code,
         coalesce(prs.ack_status, 'pending') AS ack_status,
         coalesce(prs.dispatch_status, 'sent') AS dispatch_status,
         coalesce(prs.sent_at, prs.created_at) AS dispatched_at
  INTO rec
  FROM public.partner_route_shares prs
  JOIN public.partners p ON p.id = prs.partner_id AND p.is_active = true
  LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
  WHERE prs.id = p_share_id;

  IF rec IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found', 'message', 'Ruten finnes ikke.');
  END IF;

  IF rec.company_id IS DISTINCT FROM public.get_user_company_id() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'forbidden', 'message', 'Ingen tilgang.');
  END IF;

  IF rec.dispatch_status <> 'sent' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_sent', 'message', 'Ruten er ikke varslet ennå.');
  END IF;

  IF rec.ack_status = 'accepted' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_accepted', 'message', 'Ruten er allerede akseptert.');
  END IF;

  IF rec.dispatched_at IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_dispatched', 'message', 'Ruten er ikke sendt.');
  END IF;

  ch := public.company_partner_notification_channel(
    rec.company_id, 'partner_route_reminder'
  );
  IF ch = 'none'::public.notification_channel THEN
    RETURN jsonb_build_object(
      'ok', false,
      'reason', 'channel_off',
      'message', 'Purring er av i varslingsinnstillinger.'
    );
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.sms_outbox o
    WHERE o.reference_id = rec.id
      AND o.category = 'partner_route_reminder'
      AND o.created_at > now() - interval '30 minutes'
  ) OR EXISTS (
    SELECT 1 FROM public.email_outbox e
    WHERE e.reference_id = rec.id
      AND e.category = 'partner_route_reminder'
      AND e.created_at > now() - interval '30 minutes'
  ) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'reason', 'cooldown',
      'message', 'Purring sendt nylig — vent 30 min før ny purring.'
    );
  END IF;

  msg := 'PÅMINNELSE: Rute ' || coalesce(rec.unit_code, '') ||
    ' venter på aksept i DriftPro. Logg inn og godkjenn ruten.';

  sms_n := public.notify_partner_owner_phones(
    rec.company_id, rec.partner_id, msg, 'partner_route_reminder', 'partner_route_reminder',
    'partner_route_shares', rec.id, 'Manuell purring rute'
  );
  email_n := public.notify_partner_owner_emails(
    rec.company_id, rec.partner_id,
    'Påminnelse: rute venter på aksept',
    msg, 'partner_route_reminder', 'partner_route_reminder',
    'partner_route_shares', rec.id, 'Manuell purring rute (e-post)'
  );

  IF sms_n + email_n = 0 THEN
    RETURN jsonb_build_object(
      'ok', false,
      'reason', 'no_recipient',
      'message', 'Ingen mottaker med telefon/e-post funnet.'
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'sms_queued', sms_n,
    'email_queued', email_n,
    'message', 'Purring sendt.'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.nudge_partner_route_ack(p_share_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  IF NOT (
    public.is_company_admin()
    OR public.get_user_role() IN ('admin'::public.user_role, 'superadmin'::public.user_role, 'leder'::public.user_role)
  ) THEN
    RAISE EXCEPTION 'Kun admin/leder kan sende purring';
  END IF;

  RETURN public._nudge_partner_route_ack_row(p_share_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.nudge_partner_route_ack_pending(p_day date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  rec RECORD;
  one jsonb;
  ok_cnt INT := 0;
  skip_cnt INT := 0;
  sms_total INT := 0;
  email_total INT := 0;
  v_day date;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  v_company_id := public.get_user_company_id();
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Ingen bedrift';
  END IF;

  IF NOT (
    public.is_company_admin()
    OR public.get_user_role() IN ('admin'::public.user_role, 'superadmin'::public.user_role, 'leder'::public.user_role)
  ) THEN
    RAISE EXCEPTION 'Kun admin/leder kan sende purring';
  END IF;

  v_day := coalesce(p_day, (timezone('Europe/Oslo', now()))::date);

  FOR rec IN
    SELECT prs.id
    FROM public.partner_route_shares prs
    JOIN public.partners p ON p.id = prs.partner_id AND p.is_active = true
    WHERE prs.company_id = v_company_id
      AND coalesce(prs.ack_status, 'pending') = 'pending'
      AND coalesce(prs.dispatch_status, 'sent') = 'sent'
      AND coalesce(prs.sent_at, prs.created_at) IS NOT NULL
      AND greatest(
        prs.share_date,
        (coalesce(prs.route_start_at, prs.share_date::timestamptz) AT TIME ZONE 'Europe/Oslo')::date
      ) = v_day
  LOOP
    one := public._nudge_partner_route_ack_row(rec.id);
    IF coalesce((one->>'ok')::boolean, false) THEN
      ok_cnt := ok_cnt + 1;
      sms_total := sms_total + coalesce((one->>'sms_queued')::int, 0);
      email_total := email_total + coalesce((one->>'email_queued')::int, 0);
    ELSE
      skip_cnt := skip_cnt + 1;
    END IF;
  END LOOP;

  IF ok_cnt = 0 THEN
    RETURN jsonb_build_object(
      'ok', false,
      'reason', 'none_sent',
      'skipped', skip_cnt,
      'message', CASE
        WHEN skip_cnt = 0 THEN 'Ingen ruter venter på aksept denne dagen.'
        ELSE 'Ingen purringer sendt (allerede purret, akseptert eller kanal av).'
      END
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'routes_nudged', ok_cnt,
    'skipped', skip_cnt,
    'sms_queued', sms_total,
    'email_queued', email_total,
    'message', 'Purring sendt for ' || ok_cnt || ' rute(r).'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.nudge_partner_route_ack(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nudge_partner_route_ack_pending(date) TO authenticated;

COMMENT ON FUNCTION public.nudge_partner_route_ack IS
  'Manuell purring til partner om én rute som venter på aksept.';
COMMENT ON FUNCTION public.nudge_partner_route_ack_pending IS
  'Manuell purring for alle ruter på en dag som venter på aksept.';
