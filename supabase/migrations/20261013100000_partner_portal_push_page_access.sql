-- Partner portal users do not have MAVI access_settings.areas.partners.
-- Route push was skipped with no_page_access even when portal_access allows Ruter.
-- Gate partner-scoped notifications on partners.portal_access instead.

CREATE OR REPLACE FUNCTION public.partner_portal_page_is_on(
  p_partner_id UUID,
  p_page_key TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_partner_id IS NULL OR coalesce(trim(p_page_key), '') = '' THEN false
    ELSE coalesce(
      (
        SELECT CASE
          WHEN (p.portal_access ->> p_page_key) IS NULL THEN true
          WHEN lower(trim(p.portal_access ->> p_page_key)) IN ('false', '0', 'off', 'no') THEN false
          WHEN (p.portal_access -> p_page_key) = 'false'::jsonb THEN false
          ELSE true
        END
        FROM public.partners p
        WHERE p.id = p_partner_id
      ),
      false
    )
  END;
$$;

COMMENT ON FUNCTION public.partner_portal_page_is_on(UUID, TEXT) IS
  'Partner portal page flag. Missing key = on. Explicit false = off.';

CREATE OR REPLACE FUNCTION public.partner_portal_notification_allowed(
  p_partner_id UUID,
  p_event_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_page TEXT;
BEGIN
  IF p_partner_id IS NULL OR coalesce(trim(p_event_id), '') = '' THEN
    RETURN false;
  END IF;

  v_page := CASE
    WHEN p_event_id LIKE 'partner_route%' OR p_event_id = 'partner_mass_route' THEN 'ruter'
    WHEN p_event_id LIKE 'partner_document%' OR p_event_id = 'partner_shared_routine' THEN 'dokumenter'
    WHEN p_event_id = 'partner_meeting' THEN 'moter'
    WHEN p_event_id = 'partner_deduction' THEN 'trekk'
    WHEN p_event_id = 'partner_vehicle_inspection' THEN 'bilkontroll'
    WHEN p_event_id LIKE 'vehicle_rental%' THEN 'utleie'
    WHEN p_event_id = 'partner_workforce_punch' THEN 'stempling'
    WHEN p_event_id = 'partner_weekly_summary' THEN 'oppsummering'
    WHEN p_event_id = 'partner_vehicle_inactive' THEN 'oversikt'
    ELSE 'oversikt'
  END;

  RETURN public.partner_portal_page_is_on(p_partner_id, v_page);
END;
$$;

COMMENT ON FUNCTION public.partner_portal_notification_allowed(UUID, TEXT) IS
  'Whether a partner-scoped notification may be delivered given portal_access.';

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

  -- Partner portal accounts: use portal_access, not MAVI partners area.
  IF v_role = 'samarbeidspartner' THEN
    RETURN v_scope = 'partner'
      AND public.partner_portal_notification_allowed(v_partner, p_event_id);
  END IF;

  -- Edge: profile linked to partner but not samarbeidspartner role.
  IF v_partner IS NOT NULL AND v_scope = 'partner' THEN
    RETURN public.profile_area_effectively_open(p_uid, 'partners', 'view')
      OR public.partner_portal_notification_allowed(v_partner, p_event_id);
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

GRANT EXECUTE ON FUNCTION public.partner_portal_page_is_on(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.partner_portal_notification_allowed(UUID, TEXT) TO authenticated, service_role;
