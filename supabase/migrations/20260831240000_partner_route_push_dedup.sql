-- Unngå 4× push ved én rute-utsendelse:
-- 1) Dedup i push-kø (samme rute + profil + token innen 15 min)
-- 2) Ikke dobbelt token fra user_push_devices + profiles.fcm_token
-- 3) Én push per profil (samle eier/ansatt/sjåfør)

CREATE OR REPLACE FUNCTION public.queue_push_if_allowed(
  p_company_id UUID,
  p_user_id UUID,
  p_fcm_token TEXT,
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
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enabled BOOLEAN;
  v_id UUID;
  tok TEXT := trim(coalesce(p_fcm_token, ''));
BEGIN
  IF tok = '' OR p_user_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF p_partner_scope THEN
    v_enabled := public.company_partner_push_enabled(p_company_id, p_setting_key);
  ELSE
    v_enabled := public.company_push_enabled(p_company_id, p_setting_key);
  END IF;

  IF NOT v_enabled THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'push', p_category, p_setting_key,
      tok, p_user_id, 'skipped', 'company_channel_off',
      coalesce(p_description, left(p_body, 120)), NULL, NULL, NULL, p_reference_type, p_reference_id
    );
    RETURN NULL;
  END IF;

  -- Unngå duplikat ved dobbel notify (trigger + app-RPC) eller flere mål-løkker.
  IF p_reference_id IS NOT NULL
     AND p_reference_type IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM public.push_outbox o
       WHERE o.reference_type = p_reference_type
         AND o.reference_id = p_reference_id
         AND o.profile_id = p_user_id
         AND o.fcm_token = tok
         AND o.created_at > now() - interval '15 minutes'
     ) THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.push_outbox (
    company_id, profile_id, fcm_token, title, body, data, category,
    reference_type, reference_id, description
  )
  VALUES (
    p_company_id,
    p_user_id,
    tok,
    left(trim(p_title), 120),
    left(trim(p_body), 500),
    COALESCE(p_data, '{}'::jsonb),
    p_category,
    p_reference_type,
    p_reference_id,
    coalesce(p_description, p_setting_key || ' (push)')
  )
  RETURNING id INTO v_id;

  PERFORM public.log_notification_audit(
    p_company_id, 'push', p_category, p_setting_key,
    tok, p_user_id, 'queued', NULL,
    coalesce(p_description, left(p_body, 120)), NULL, NULL, NULL, p_reference_type, p_reference_id
  );

  RETURN v_id;
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
BEGIN
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

  -- Legacy profiles.fcm_token kun når ingen aktive enheter er registrert.
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

  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_partner_route_driver_push(p_route_share_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  shift_name TEXT;
  driver_title TEXT;
  driver_body TEXT;
  d RECORD;
  n INT := 0;
  owner_only BOOLEAN;
BEGIN
  SELECT
    prs.*,
    pv.unit_code,
    pv.registration_number AS vehicle_reg,
    p.name AS partner_name,
    p.is_active AS partner_is_active,
    coalesce(p.routes_owner_only, true) AS routes_owner_only
  INTO r
  FROM public.partner_route_shares prs
  LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
  LEFT JOIN public.partners p ON p.id = prs.partner_id
  WHERE prs.id = p_route_share_id;

  IF r IS NULL
     OR coalesce(r.partner_is_active, false) = false
     OR coalesce(r.dispatch_status, 'sent') <> 'sent'
     OR r.partner_vehicle_id IS NULL THEN
    RETURN 0;
  END IF;

  IF NOT public.partner_route_wants_channel(r.notify_channels, 'app')
     OR NOT public.company_partner_push_enabled(r.company_id, 'partner_route') THEN
    RETURN 0;
  END IF;

  owner_only := coalesce(r.routes_owner_only, true);

  SELECT name INTO shift_name FROM public.fleet_shift_definitions WHERE id = r.shift_id;

  driver_title := 'Ny rute i DriftPro';
  driver_body := 'Ny rute på ' || coalesce(r.unit_code, 'bil') ||
    CASE WHEN r.vehicle_reg IS NOT NULL AND trim(r.vehicle_reg) <> '' THEN ' (' || trim(r.vehicle_reg) || ')' ELSE '' END ||
    CASE WHEN shift_name IS NOT NULL THEN ' · ' || shift_name ELSE '' END ||
    '. Åpne appen for PDF og godkjenning.';

  -- Én push per profil (eier/admin, ansatt med bil-tilgang, evt. sjåfør).
  FOR d IN
    SELECT DISTINCT t.profile_id
    FROM (
      SELECT ppa.profile_id
      FROM public.partner_portal_accounts ppa
      JOIN public.profiles pr ON pr.id = ppa.profile_id AND coalesce(pr.is_active, true) = true
      WHERE ppa.partner_id = r.partner_id
        AND ppa.is_active = true
        AND ppa.profile_id IS NOT NULL
        AND coalesce(ppa.account_kind, 'owner') IN ('owner', 'admin')
        AND ppa.partner_vehicle_id IS NULL

      UNION ALL

      SELECT s.profile_id
      FROM public.partner_staff s
      JOIN public.partner_staff_route_vehicles srv ON srv.staff_id = s.id
      JOIN public.profiles pr ON pr.id = s.profile_id AND coalesce(pr.is_active, true) = true
      WHERE s.partner_id = r.partner_id
        AND s.is_active = true
        AND s.can_manage_routes = true
        AND s.profile_id IS NOT NULL
        AND srv.partner_vehicle_id = r.partner_vehicle_id

      UNION ALL

      SELECT ppa.profile_id
      FROM public.partner_portal_accounts ppa
      JOIN public.profiles pr ON pr.id = ppa.profile_id AND coalesce(pr.is_active, true) = true
      WHERE NOT owner_only
        AND ppa.partner_vehicle_id = r.partner_vehicle_id
        AND ppa.is_active = true
        AND coalesce(ppa.account_kind, 'driver') = 'driver'
        AND ppa.profile_id IS NOT NULL
    ) t
    WHERE t.profile_id IS NOT NULL
  LOOP
    n := n + public.queue_push_to_profile_if_allowed(
      r.company_id, d.profile_id, driver_title, driver_body,
      'partner_route', 'partner_route_shares', p_route_share_id,
      'partner_route', 'Ny rute (push)', true,
      jsonb_build_object('type', 'partner_route', 'route_share_id', p_route_share_id::text)
    );
  END LOOP;

  IF n = 0 THEN
    PERFORM public.log_notification_audit(
      r.company_id, 'push', 'partner_route', 'partner_route',
      NULL, NULL, 'skipped', 'no_push_devices',
      'Ingen aktiv push-enhet — logg inn i appen og slå på varsler',
      NULL, NULL, NULL,
      'partner_route_shares', p_route_share_id
    );
  END IF;

  RETURN n;
END;
$$;

COMMENT ON FUNCTION public.queue_push_if_allowed IS
  'Køer push hvis firmakanal er på; dedup samme rute+profil+token innen 15 min.';
COMMENT ON FUNCTION public.queue_push_to_profile_if_allowed IS
  'Sender til alle aktive enheter; legacy profiles.fcm_token kun uten user_push_devices.';
COMMENT ON FUNCTION public.notify_partner_route_driver_push IS
  'Push ved rute-utsendelse — én kø per profil (eier/ansatt/sjåfør).';
