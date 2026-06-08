-- Kun eksplisitt valgte mottakere for interne MAVI-varsler.
-- Slår av automatisk daglig SMS «ruter venter på partner-aksept» (cron).
-- Manuell utsending via send_pending_routes_digest_now() fra appen.

DO $$
BEGIN
  PERFORM cron.unschedule('mavi-pending-routes-digest');
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

UPDATE public.notification_event_definitions
SET default_recipient_rule = 'none'
WHERE id IN (
  'partner_route_ack_internal',
  'partner_route_pending_internal',
  'sap_route_received',
  'partner_document_internal',
  'partner_rental_internal',
  'partner_deactivated_internal',
  'user_approval',
  'absence_request',
  'ticket_new',
  'hms_ros_avvik_signal',
  'hms_general',
  'equipment',
  'general'
);

CREATE OR REPLACE FUNCTION public.profile_default_event_subscription(
  p_company_id UUID,
  p_profile_id UUID,
  p_event_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d public.notification_event_definitions%ROWTYPE;
  p public.profiles%ROWTYPE;
BEGIN
  SELECT * INTO d
  FROM public.notification_event_definitions
  WHERE id = p_event_id AND is_active = true;

  IF NOT FOUND OR d.default_recipient_rule <> 'assignee_default' THEN
    RETURN false;
  END IF;

  SELECT * INTO p
  FROM public.profiles
  WHERE id = p_profile_id AND company_id = p_company_id;

  IF NOT FOUND OR NOT p.is_active OR NOT p.is_approved THEN
    RETURN false;
  END IF;

  RETURN p.role IN (
    'leder'::public.user_role,
    'admin'::public.user_role,
    'superadmin'::public.user_role
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.profile_receives_notification_event(
  p_company_id UUID,
  p_profile_id UUID,
  p_setting_key TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_id TEXT;
  v_rule TEXT;
  v_assignable BOOLEAN;
  v_subscribed BOOLEAN;
  v_channel public.notification_channel;
  v_found BOOLEAN := false;
  p public.profiles%ROWTYPE;
BEGIN
  SELECT * INTO p
  FROM public.profiles
  WHERE id = p_profile_id AND company_id = p_company_id;

  IF NOT FOUND OR NOT p.is_active OR NOT p.is_approved THEN
    RETURN false;
  END IF;

  SELECT d.id, d.default_recipient_rule, d.assignable_to_employees
  INTO v_event_id, v_rule, v_assignable
  FROM public.notification_event_definitions d
  WHERE d.setting_key = p_setting_key
    AND d.scope = 'mavi'
    AND d.is_active = true
  LIMIT 1;

  IF v_event_id IS NULL THEN
    RETURN false;
  END IF;

  IF NOT v_assignable THEN
    RETURN true;
  END IF;

  SELECT s.subscribed, s.channel, true
  INTO v_subscribed, v_channel, v_found
  FROM public.profile_notification_subscriptions s
  WHERE s.profile_id = p_profile_id AND s.event_id = v_event_id;

  IF v_found THEN
    RETURN v_subscribed AND v_channel <> 'none'::public.notification_channel;
  END IF;

  IF v_rule = 'assignee_default' THEN
    RETURN p.role IN (
      'leder'::public.user_role,
      'admin'::public.user_role,
      'superadmin'::public.user_role
    );
  END IF;

  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_mavi_partner_internal(
  p_company_id UUID,
  p_setting_key TEXT,
  p_subject TEXT,
  p_body TEXT,
  p_sms_short TEXT,
  p_category TEXT,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id UUID DEFAULT NULL,
  p_description TEXT DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  n INT := 0;
BEGIN
  IF NOT public.company_sms_enabled(p_company_id, p_setting_key)
     AND NOT public.company_email_enabled(p_company_id, p_setting_key) THEN
    RETURN 0;
  END IF;

  FOR rec IN
    SELECT
      p.id,
      p.email,
      coalesce(p.phone_normalized, p.phone) AS phone,
      s.channel
    FROM public.profiles p
    INNER JOIN public.profile_notification_subscriptions s
      ON s.profile_id = p.id
      AND s.subscribed = true
      AND s.channel <> 'none'::public.notification_channel
    INNER JOIN public.notification_event_definitions d
      ON d.id = s.event_id
      AND d.setting_key = p_setting_key
      AND d.scope = 'mavi'
      AND d.is_active = true
    WHERE p.company_id = p_company_id
      AND p.is_active = true
      AND p.is_approved = true
      AND p.partner_id IS NULL
      AND p.role <> 'samarbeidspartner'::public.user_role
  LOOP
    IF rec.channel IN ('sms'::public.notification_channel, 'both'::public.notification_channel)
       AND public.company_sms_enabled(p_company_id, p_setting_key)
       AND coalesce(rec.phone, '') <> '' THEN
      PERFORM public.queue_sms_if_allowed(
        p_company_id, rec.id, rec.phone,
        p_sms_short, p_category, p_reference_type, p_reference_id,
        p_setting_key, p_description, false
      );
      n := n + 1;
    END IF;

    IF rec.channel IN ('email'::public.notification_channel, 'both'::public.notification_channel)
       AND public.company_email_enabled(p_company_id, p_setting_key)
       AND coalesce(rec.email, '') <> '' THEN
      PERFORM public.queue_email_if_allowed(
        p_company_id, rec.id, rec.email, p_subject, p_body,
        p_category, p_reference_type, p_reference_id,
        p_setting_key, p_description, false
      );
      n := n + 1;
    END IF;
  END LOOP;

  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_company_notification_recipient_matrix(p_company_id uuid)
RETURNS TABLE (
  profile_id uuid,
  profile_name text,
  profile_email text,
  profile_role text,
  department_name text,
  event_id text,
  setting_key text,
  event_title text,
  category_group text,
  subscribed boolean,
  channel text,
  is_explicit boolean,
  default_recipient_rule text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_company_id <> public.get_user_company_id() THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  RETURN QUERY
  SELECT
    p.id AS profile_id,
    p.full_name AS profile_name,
    p.email AS profile_email,
    p.role::text AS profile_role,
    d.name AS department_name,
    e.id AS event_id,
    e.setting_key,
    e.title AS event_title,
    e.category_group,
    CASE
      WHEN s.id IS NOT NULL THEN s.subscribed
      ELSE public.profile_default_event_subscription(p_company_id, p.id, e.id)
    END AS subscribed,
    CASE
      WHEN s.id IS NOT NULL THEN s.channel::text
      WHEN public.profile_default_event_subscription(p_company_id, p.id, e.id) THEN 'both'::text
      ELSE 'none'::text
    END AS channel,
    (s.id IS NOT NULL) AS is_explicit,
    e.default_recipient_rule
  FROM public.profiles p
  LEFT JOIN public.departments d ON d.id = p.department_id
  CROSS JOIN public.notification_event_definitions e
  LEFT JOIN public.profile_notification_subscriptions s
    ON s.profile_id = p.id AND s.event_id = e.id
  WHERE p.company_id = p_company_id
    AND p.is_active = true
    AND p.is_approved = true
    AND p.partner_id IS NULL
    AND p.role <> 'samarbeidspartner'::public.user_role
    AND e.scope = 'mavi'
    AND e.is_active = true
    AND e.assignable_to_employees = true
  ORDER BY p.full_name, e.category_group, e.sort_order, e.title;
END;
$$;

CREATE OR REPLACE FUNCTION public.send_pending_routes_digest_now(p_company_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  cnt int;
  sub text;
  body text;
  sms_txt text;
  sent int;
  recipient_count int;
BEGIN
  v_company_id := coalesce(p_company_id, public.get_user_company_id());

  IF v_company_id IS NULL OR v_company_id <> public.get_user_company_id() THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  IF NOT (
    public.is_company_admin()
    OR public.get_user_role() IN ('admin'::public.user_role, 'superadmin'::public.user_role, 'leder'::public.user_role)
  ) THEN
    RAISE EXCEPTION 'Kun admin/leder kan sende oppsummering';
  END IF;

  SELECT count(*)::int INTO recipient_count
  FROM public.profile_notification_subscriptions s
  JOIN public.notification_event_definitions d ON d.id = s.event_id
  WHERE s.company_id = v_company_id
    AND d.setting_key = 'partner_route_pending_internal'
    AND s.subscribed = true
    AND s.channel <> 'none'::public.notification_channel;

  IF recipient_count = 0 THEN
    RETURN jsonb_build_object(
      'ok', false,
      'reason', 'no_recipients',
      'message', 'Ingen mottakere valgt. Gå til Mottakere og velg hvem som skal få «Ruter venter aksept».'
    );
  END IF;

  SELECT count(*)::int INTO cnt
  FROM public.partner_route_shares prs
  JOIN public.partners p ON p.id = prs.partner_id AND p.is_active = true
  WHERE prs.company_id = v_company_id
    AND coalesce(prs.ack_status, 'pending') = 'pending'
    AND coalesce(prs.dispatch_status, 'sent') = 'sent'
    AND prs.created_at < now() - interval '6 hours';

  IF cnt = 0 THEN
    RETURN jsonb_build_object(
      'ok', false,
      'reason', 'no_pending_routes',
      'message', 'Ingen ruter venter på partner-aksept akkurat nå.'
    );
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.sms_outbox o
    WHERE o.company_id = v_company_id
      AND o.category = 'partner_route_pending'
      AND o.created_at > now() - interval '20 hours'
  ) OR EXISTS (
    SELECT 1 FROM public.email_outbox o
    WHERE o.company_id = v_company_id
      AND o.category = 'partner_route_pending'
      AND o.created_at > now() - interval '20 hours'
  ) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'reason', 'already_sent',
      'message', 'Oppsummering er allerede sendt de siste 20 timene.'
    );
  END IF;

  sub := 'MAVI: ' || cnt || ' ruter venter på partner-aksept';
  body := 'Det finnes ' || cnt || ' rute(r) som samarbeidspartnere ikke har akseptert ennå. Sjekk ruteplanlegger i DriftPro.';
  sms_txt := sub;

  sent := public.notify_mavi_partner_internal(
    v_company_id,
    'partner_route_pending_internal',
    sub, body, sms_txt,
    'partner_route_pending', NULL, NULL,
    'Manuell: ventende rute-aksept'
  );

  RETURN jsonb_build_object(
    'ok', true,
    'pending_routes', cnt,
    'recipient_count', recipient_count,
    'messages_queued', sent,
    'message', 'Oppsummering sendt til ' || recipient_count || ' valgte mottaker(e).'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.enqueue_mavi_pending_routes_digest()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN 0;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_pending_routes_digest_now(uuid) TO authenticated;

COMMENT ON FUNCTION public.notify_mavi_partner_internal IS
  'Interne MAVI-varsler — kun ansatte med eksplisitt abonnement i Mottakere-matrisen.';
COMMENT ON FUNCTION public.send_pending_routes_digest_now IS
  'Manuell SMS/e-post: ventende ruter — kun til valgte mottakere (maks én gang per 20t).';
