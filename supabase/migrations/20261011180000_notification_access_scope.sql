-- Varsler følger sidetilgang. Eksplisitt av i access_settings vinner også for superadmin.
-- Bryter øverst setter én kanal på alle varsler brukeren faktisk har tilgang til.

CREATE OR REPLACE FUNCTION public.profile_area_effectively_open(
  p_uid UUID,
  p_area TEXT,
  p_action TEXT DEFAULT 'view'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_settings JSONB;
  v_emp TEXT;
  v_approved BOOLEAN;
  v_active BOOLEAN;
  v_cursor TEXT;
  v_obj JSONB;
  v_act TEXT;
BEGIN
  IF p_uid IS NULL OR coalesce(trim(p_area), '') = '' THEN
    RETURN false;
  END IF;

  SELECT p.role::text, p.access_settings, p.employee_number, p.is_approved, p.is_active
  INTO v_role, v_settings, v_emp, v_approved, v_active
  FROM public.profiles p
  WHERE p.id = p_uid;

  IF NOT FOUND OR v_active IS DISTINCT FROM true THEN
    RETURN false;
  END IF;

  v_settings := coalesce(v_settings, '{}'::jsonb);

  IF coalesce((v_settings->>'version')::int, 0) = 2 THEN
    v_cursor := p_area;
    LOOP
      v_obj := v_settings -> 'areas' -> v_cursor;
      v_act := CASE
        WHEN v_cursor = p_area THEN lower(trim(p_action))
        ELSE 'view'
      END;
      IF v_obj IS NOT NULL
         AND v_obj ? v_act
         AND coalesce((v_obj ->> v_act)::boolean, false) IS NOT TRUE THEN
        RETURN false;
      END IF;
      EXIT WHEN strpos(v_cursor, '.') = 0;
      v_cursor := regexp_replace(v_cursor, '\.[^.]+$', '');
    END LOOP;

    IF p_area = 'more.partnere'
       AND NOT public.profile_area_effectively_open(p_uid, 'partners', 'view') THEN
      RETURN false;
    END IF;
    IF p_area = 'more.undersokelser'
       AND NOT public.profile_area_effectively_open(p_uid, 'surveys', 'view') THEN
      RETURN false;
    END IF;
  END IF;

  IF v_role = 'superadmin' OR v_emp IN ('100', '144', '25') THEN
    RETURN true;
  END IF;

  IF v_approved IS DISTINCT FROM true THEN
    RETURN false;
  END IF;

  IF v_role = 'ansatt' AND (
    p_area = 'more.avdelinger'
    OR p_area = 'admin.avdelinger_rediger'
    OR p_area LIKE 'more.avdelinger.%'
  ) THEN
    RETURN false;
  END IF;

  RETURN public.profile_has_access(p_uid, p_area, p_action);
END;
$$;

CREATE OR REPLACE FUNCTION public.profile_notification_event_open(
  p_uid UUID,
  p_event_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_partner UUID;
  v_id TEXT;
  v_scope TEXT;
  v_active BOOLEAN;
  v_leader BOOLEAN;
BEGIN
  IF p_uid IS NULL OR coalesce(p_event_id, '') = '' THEN
    RETURN false;
  END IF;

  SELECT p.role::text, p.partner_id
  INTO v_role, v_partner
  FROM public.profiles p
  WHERE p.id = p_uid;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  SELECT d.id, d.scope, d.is_active
  INTO v_id, v_scope, v_active
  FROM public.notification_event_definitions d
  WHERE d.id = p_event_id OR d.setting_key = p_event_id
  ORDER BY CASE WHEN d.id = p_event_id THEN 0 ELSE 1 END
  LIMIT 1;

  IF NOT FOUND OR NOT coalesce(v_active, false) THEN
    RETURN false;
  END IF;

  p_event_id := v_id;

  IF v_role = 'samarbeidspartner' OR v_partner IS NOT NULL THEN
    RETURN v_scope = 'partner'
      AND public.profile_area_effectively_open(p_uid, 'partners', 'view');
  END IF;

  IF v_scope <> 'mavi' THEN
    RETURN false;
  END IF;

  v_leader := public.profile_is_registered_department_leader(p_uid);

  IF p_event_id = 'absence_decision' THEN
    RETURN public.profile_area_effectively_open(p_uid, 'fravaer', 'view');
  ELSIF p_event_id = 'absence_request' THEN
    RETURN public.profile_area_effectively_open(p_uid, 'fravaer.godkjenn', 'approve')
      OR public.profile_area_effectively_open(p_uid, 'fravaer', 'approve')
      OR public.profile_area_effectively_open(p_uid, 'fravaer.team', 'view')
      OR (
        v_leader
        AND public.profile_area_effectively_open(p_uid, 'fravaer', 'view')
      );
  ELSIF p_event_id = 'ticket_status' THEN
    RETURN public.profile_area_effectively_open(p_uid, 'avvik', 'view')
      OR public.profile_area_effectively_open(p_uid, 'avvik.nytt', 'view');
  ELSIF p_event_id IN ('ticket_new', 'ticket_assigned', 'ticket_critical') THEN
    RETURN public.profile_area_effectively_open(p_uid, 'avvik.behandle', 'approve')
      OR public.profile_area_effectively_open(p_uid, 'avvik.koordinere', 'view')
      OR public.profile_area_effectively_open(p_uid, 'avvik.admin', 'view')
      OR (
        v_leader
        AND public.profile_area_effectively_open(p_uid, 'avvik', 'view')
      );
  ELSIF p_event_id IN ('hms_risk_assigned', 'hms_ros_avvik_signal') THEN
    RETURN public.profile_area_effectively_open(p_uid, 'hms.risiko', 'view');
  ELSIF p_event_id IN ('hms_sja_assigned', 'hms_sja_expired') THEN
    RETURN public.profile_area_effectively_open(p_uid, 'hms.sja', 'view');
  ELSIF p_event_id = 'hms_general' THEN
    RETURN public.profile_area_effectively_open(p_uid, 'hms', 'view')
      OR public.profile_area_effectively_open(p_uid, 'hms.risiko', 'view')
      OR public.profile_area_effectively_open(p_uid, 'hms.sja', 'view');
  ELSIF p_event_id = 'equipment' THEN
    RETURN public.profile_area_effectively_open(p_uid, 'hms.utstyr', 'view');
  ELSIF p_event_id = 'user_approval' THEN
    RETURN public.profile_area_effectively_open(p_uid, 'more.brukergodkjenning', 'view');
  ELSIF p_event_id IN (
    'partner_route_ack_internal',
    'partner_route_pending_internal',
    'sap_route_received'
  ) THEN
    RETURN public.profile_area_effectively_open(p_uid, 'partners', 'view')
      OR public.profile_area_effectively_open(p_uid, 'partners.fleet', 'view')
      OR public.profile_area_effectively_open(p_uid, 'partners.tabs.ruter', 'view');
  ELSIF p_event_id = 'partner_rental_internal' THEN
    RETURN public.profile_area_effectively_open(p_uid, 'partners.vehicle_rental', 'view');
  ELSIF p_event_id = 'partner_document_internal' THEN
    RETURN public.profile_area_effectively_open(p_uid, 'partners.tabs.dokumenter', 'view')
      OR public.profile_area_effectively_open(p_uid, 'partners', 'view');
  ELSIF p_event_id = 'partner_deactivated_internal' THEN
    RETURN public.profile_area_effectively_open(p_uid, 'partners.admin', 'view')
      OR public.profile_area_effectively_open(p_uid, 'partners', 'delete');
  ELSIF p_event_id = 'general' THEN
    RETURN public.profile_area_effectively_open(p_uid, 'dashboard', 'view')
      OR public.profile_area_effectively_open(p_uid, 'more', 'view');
  END IF;

  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.profile_notification_delivery_allowed(
  p_uid UUID,
  p_setting_key TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_uid IS NULL OR coalesce(p_setting_key, '') = '' THEN true
    WHEN NOT EXISTS (
      SELECT 1
      FROM public.notification_event_definitions d
      WHERE d.is_active = true
        AND (d.id = p_setting_key OR d.setting_key = p_setting_key)
    ) THEN true
    ELSE public.profile_notification_event_open(p_uid, p_setting_key)
  END;
$$;

CREATE OR REPLACE FUNCTION public.profile_can_configure_notification_event(
  p_profile_id UUID,
  p_event_id TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.profile_notification_event_open(p_profile_id, p_event_id);
$$;

CREATE OR REPLACE FUNCTION public.get_my_notification_preferences()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_events JSONB;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT coalesce(jsonb_agg(row_to_json(x)::jsonb ORDER BY x.sort_order, x.title), '[]'::jsonb)
  INTO v_events
  FROM (
    SELECT
      d.id,
      d.title,
      d.subtitle,
      d.category_group AS category,
      d.sort_order,
      CASE
        WHEN s.event_id IS NOT NULL THEN coalesce(s.sms_enabled, true)
        WHEN public.user_effective_notify_channel(v_uid) IN (
          'none'::public.notification_channel,
          'email'::public.notification_channel
        ) THEN false
        ELSE true
      END AS sms,
      CASE
        WHEN s.event_id IS NOT NULL THEN coalesce(s.email_enabled, true)
        WHEN public.user_effective_notify_channel(v_uid) IN (
          'none'::public.notification_channel,
          'sms'::public.notification_channel
        ) THEN false
        ELSE true
      END AS email,
      CASE
        WHEN s.event_id IS NOT NULL THEN coalesce(s.push_enabled, true)
        WHEN public.user_effective_notify_channel(v_uid) = 'none'::public.notification_channel
          THEN false
        ELSE true
      END AS push
    FROM public.notification_event_definitions d
    LEFT JOIN public.profile_notification_subscriptions s
      ON s.profile_id = v_uid AND s.event_id = d.id
    WHERE d.is_active = true
      AND public.profile_notification_event_open(v_uid, d.id)
  ) x;

  RETURN jsonb_build_object(
    'is_manager', jsonb_array_length(v_events) > 2,
    'events', v_events
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.set_my_notification_channel(
  p_channel TEXT,
  p_enabled BOOLEAN
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  r RECORD;
  n INT := 0;
  v_sms BOOLEAN;
  v_email BOOLEAN;
  v_push BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  IF p_channel NOT IN ('sms', 'email', 'push') THEN
    RAISE EXCEPTION 'Ukjent kanal';
  END IF;

  FOR r IN
    SELECT
      d.id,
      coalesce(s.sms_enabled, true) AS sms_enabled,
      coalesce(s.email_enabled, true) AS email_enabled,
      coalesce(s.push_enabled, true) AS push_enabled
    FROM public.notification_event_definitions d
    LEFT JOIN public.profile_notification_subscriptions s
      ON s.profile_id = v_uid AND s.event_id = d.id
    WHERE d.is_active = true
      AND public.profile_notification_event_open(v_uid, d.id)
  LOOP
    v_sms := CASE WHEN p_channel = 'sms' THEN coalesce(p_enabled, false) ELSE r.sms_enabled END;
    v_email := CASE WHEN p_channel = 'email' THEN coalesce(p_enabled, false) ELSE r.email_enabled END;
    v_push := CASE WHEN p_channel = 'push' THEN coalesce(p_enabled, false) ELSE r.push_enabled END;
    PERFORM public.set_my_notification_preference(r.id, v_sms, v_email, v_push);
    n := n + 1;
  END LOOP;

  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.profile_event_allows_sms(
  p_company_id uuid,
  p_profile_id uuid,
  p_setting_key text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  sub record;
  receives boolean;
BEGIN
  IF p_profile_id IS NOT NULL
     AND NOT public.profile_notification_delivery_allowed(p_profile_id, p_setting_key) THEN
    RETURN false;
  END IF;

  IF NOT public.company_sms_enabled(p_company_id, p_setting_key) THEN
    RETURN false;
  END IF;

  IF p_profile_id IS NOT NULL AND NOT public.user_accepts_sms(p_profile_id) THEN
    RETURN false;
  END IF;

  IF p_profile_id IS NOT NULL
     AND public.profile_has_personal_channel_row(p_profile_id, p_setting_key) THEN
    RETURN public.profile_personal_channel_on(p_profile_id, p_setting_key, 'sms');
  END IF;

  IF p_profile_id IS NOT NULL THEN
    IF public.user_effective_notify_channel(p_profile_id) IN (
      'none'::public.notification_channel,
      'email'::public.notification_channel
    ) THEN
      RETURN false;
    END IF;
  END IF;

  SELECT * INTO sub FROM public.profile_subscription_row(p_profile_id, p_setting_key);
  IF sub.found THEN
    IF NOT sub.subscribed OR sub.channel IN (
      'none'::public.notification_channel,
      'email'::public.notification_channel
    ) THEN
      RETURN false;
    END IF;
    RETURN true;
  END IF;

  IF p_setting_key IN ('ticket_status', 'absence_decision') THEN
    RETURN true;
  END IF;

  receives := public.profile_receives_notification_event(
    p_company_id, p_profile_id, p_setting_key
  );
  RETURN receives;
END;
$$;

CREATE OR REPLACE FUNCTION public.profile_event_allows_email(
  p_company_id uuid,
  p_profile_id uuid,
  p_setting_key text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  sub record;
  receives boolean;
BEGIN
  IF p_profile_id IS NOT NULL
     AND NOT public.profile_notification_delivery_allowed(p_profile_id, p_setting_key) THEN
    RETURN false;
  END IF;

  IF NOT public.company_email_enabled(p_company_id, p_setting_key) THEN
    RETURN false;
  END IF;

  IF p_profile_id IS NOT NULL AND NOT public.user_accepts_email(p_profile_id) THEN
    RETURN false;
  END IF;

  IF p_profile_id IS NOT NULL
     AND public.profile_has_personal_channel_row(p_profile_id, p_setting_key) THEN
    RETURN public.profile_personal_channel_on(p_profile_id, p_setting_key, 'email');
  END IF;

  IF p_profile_id IS NOT NULL THEN
    IF public.user_effective_notify_channel(p_profile_id) IN (
      'none'::public.notification_channel,
      'sms'::public.notification_channel
    ) THEN
      RETURN false;
    END IF;
  END IF;

  SELECT * INTO sub FROM public.profile_subscription_row(p_profile_id, p_setting_key);
  IF sub.found THEN
    IF NOT sub.subscribed OR sub.channel IN (
      'none'::public.notification_channel,
      'sms'::public.notification_channel
    ) THEN
      RETURN false;
    END IF;
    RETURN true;
  END IF;

  IF p_setting_key IN ('ticket_status', 'absence_decision') THEN
    RETURN true;
  END IF;

  receives := public.profile_receives_notification_event(
    p_company_id, p_profile_id, p_setting_key
  );
  RETURN receives;
END;
$$;

CREATE OR REPLACE FUNCTION public.queue_push_to_profile_if_allowed(
  p_company_id UUID,
  p_profile_id UUID,
  p_title TEXT,
  p_body TEXT,
  p_category TEXT,
  p_reference_type TEXT,
  p_reference_id UUID,
  p_setting_key TEXT,
  p_description TEXT DEFAULT NULL,
  p_partner_scope BOOLEAN DEFAULT false,
  p_data JSONB DEFAULT '{}'::jsonb
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d RECORD;
  n INT := 0;
  sent TEXT[] := ARRAY[]::TEXT[];
  v_has_devices BOOLEAN := false;
  v_enabled BOOLEAN;
BEGIN
  IF p_profile_id IS NOT NULL
     AND NOT public.profile_notification_delivery_allowed(p_profile_id, p_setting_key) THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'push', p_category, p_setting_key,
      NULL, p_profile_id, 'skipped', 'no_page_access',
      coalesce(p_description, left(p_body, 120)), NULL, NULL, NULL, p_reference_type, p_reference_id
    );
    RETURN 0;
  END IF;

  IF p_partner_scope THEN
    v_enabled := public.company_partner_push_enabled(p_company_id, p_setting_key);
  ELSE
    v_enabled := public.company_push_enabled(p_company_id, p_setting_key);
  END IF;

  IF NOT v_enabled THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'push', p_category, p_setting_key,
      NULL, p_profile_id, 'skipped', 'company_channel_off',
      coalesce(p_description, left(p_body, 120)), NULL, NULL, NULL, p_reference_type, p_reference_id
    );
    RETURN 0;
  END IF;

  IF p_profile_id IS NOT NULL AND (
    (
      public.profile_has_personal_channel_row(p_profile_id, p_setting_key)
      AND NOT public.profile_personal_channel_on(p_profile_id, p_setting_key, 'push')
    )
    OR (
      NOT public.profile_has_personal_channel_row(p_profile_id, p_setting_key)
      AND public.user_effective_notify_channel(p_profile_id) = 'none'::public.notification_channel
    )
  ) THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'push', p_category, p_setting_key,
      NULL, p_profile_id, 'skipped', 'personal_channel_off',
      coalesce(p_description, left(p_body, 120)), NULL, NULL, NULL, p_reference_type, p_reference_id
    );
    RETURN 0;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.user_push_devices upd
    WHERE upd.profile_id = p_profile_id
      AND upd.is_active = true
      AND nullif(trim(upd.fcm_token), '') IS NOT NULL
  ) INTO v_has_devices;

  FOR d IN
    SELECT DISTINCT ON (upd.fcm_token)
      upd.fcm_token
    FROM public.user_push_devices upd
    WHERE upd.profile_id = p_profile_id
      AND upd.is_active = true
    ORDER BY upd.fcm_token, upd.last_seen_at DESC
  LOOP
    IF d.fcm_token IS NOT NULL AND NOT (d.fcm_token = ANY (sent)) THEN
      IF public.queue_push_if_allowed(
        p_company_id, p_profile_id, d.fcm_token, p_title, p_body,
        p_category, p_reference_type, p_reference_id, p_setting_key, p_description,
        p_partner_scope, p_data
      ) IS NOT NULL THEN
        n := n + 1;
      END IF;
      sent := array_append(sent, d.fcm_token);
    END IF;
  END LOOP;

  IF NOT v_has_devices THEN
    FOR d IN
      SELECT pr.fcm_token
      FROM public.profiles pr
      WHERE pr.id = p_profile_id
        AND nullif(trim(pr.fcm_token), '') IS NOT NULL
    LOOP
      IF d.fcm_token IS NOT NULL AND NOT (d.fcm_token = ANY (sent)) THEN
        IF public.queue_push_if_allowed(
          p_company_id, p_profile_id, d.fcm_token, p_title, p_body,
          p_category, p_reference_type, p_reference_id, p_setting_key, p_description,
          p_partner_scope, p_data
        ) IS NOT NULL THEN
          n := n + 1;
        END IF;
        sent := array_append(sent, d.fcm_token);
      END IF;
    END LOOP;
  END IF;

  IF n = 0 THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'push', p_category, p_setting_key,
      NULL, p_profile_id, 'skipped', 'no_push_devices',
      'Ingen aktiv push-enhet — logg inn i appen og slå på varsler',
      NULL, NULL, NULL, p_reference_type, p_reference_id
    );
  END IF;

  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.profile_area_effectively_open(UUID, TEXT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.profile_notification_event_open(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.profile_notification_delivery_allowed(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_my_notification_channel(TEXT, BOOLEAN) TO authenticated;

NOTIFY pgrst, 'reload schema';
