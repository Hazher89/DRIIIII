-- Fravær/ferie-varsler: avdelingsledere må gjenkjennes selv om de kun er satt via
-- departments.leader_id eller rolle «leder» + avdeling (uten rad i department_leaders).

-- ── Synkroniser avdelingsledere fra eksisterende data ───────────────────────

INSERT INTO public.department_leaders (department_id, profile_id)
SELECT d.id, d.leader_id
FROM public.departments d
WHERE d.leader_id IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.department_leaders (department_id, profile_id)
SELECT p.department_id, p.id
FROM public.profiles p
WHERE p.department_id IS NOT NULL
  AND p.role = 'leder'::public.user_role
  AND p.is_active = true
  AND p.is_approved = true
ON CONFLICT DO NOTHING;

-- ── Hjelpefunksjon: leder for gitt avdeling ─────────────────────────────────

CREATE OR REPLACE FUNCTION public.profile_leads_department(
  p_profile_id uuid,
  p_department_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_department_id IS NOT NULL AND (
    EXISTS (
      SELECT 1
      FROM public.department_leaders dl
      WHERE dl.profile_id = p_profile_id
        AND dl.department_id = p_department_id
    )
    OR EXISTS (
      SELECT 1
      FROM public.departments d
      WHERE d.id = p_department_id
        AND d.leader_id = p_profile_id
    )
    OR EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = p_profile_id
        AND p.department_id = p_department_id
        AND p.role = 'leder'::public.user_role
        AND p.is_active = true
        AND p.is_approved = true
    )
  );
$$;

COMMENT ON FUNCTION public.profile_leads_department(uuid, uuid) IS
  'True når profilen er avdelingsleder (junction, primary leader_id eller rolle leder i avdelingen).';

-- Hold department_leaders i sync når departments.leader_id endres
CREATE OR REPLACE FUNCTION public.sync_department_leader_id_to_junction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.leader_id IS NOT NULL THEN
    INSERT INTO public.department_leaders (department_id, profile_id)
    VALUES (NEW.id, NEW.leader_id)
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_department_leader_junction ON public.departments;
CREATE TRIGGER trg_sync_department_leader_junction
  AFTER INSERT OR UPDATE OF leader_id ON public.departments
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_department_leader_id_to_junction();

-- ── Utvid mottaker-sjekk for avdelingsvarsler ───────────────────────────────

CREATE OR REPLACE FUNCTION public.profile_receives_for_department(
  p_company_id uuid,
  p_profile_id uuid,
  p_department_id uuid,
  p_setting_key text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_id text;
  v_explicit boolean;
  v_found boolean := false;
  p public.profiles%ROWTYPE;
BEGIN
  SELECT * INTO p
  FROM public.profiles
  WHERE id = p_profile_id AND company_id = p_company_id;

  IF NOT FOUND OR NOT p.is_active OR NOT p.is_approved THEN
    RETURN false;
  END IF;

  SELECT d.id INTO v_event_id
  FROM public.notification_event_definitions d
  WHERE d.setting_key = p_setting_key
    AND d.scope = 'mavi'
    AND d.is_active = true
  LIMIT 1;

  IF v_event_id IS NOT NULL THEN
    SELECT s.subscribed, true INTO v_explicit, v_found
    FROM public.profile_notification_subscriptions s
    WHERE s.profile_id = p_profile_id AND s.event_id = v_event_id;

    IF v_found THEN
      RETURN v_explicit;
    END IF;
  END IF;

  IF p.role IN ('admin'::public.user_role, 'superadmin'::public.user_role) THEN
    IF p_setting_key IN ('absence_request', 'ticket_new') THEN
      RETURN true;
    END IF;
    IF v_event_id IS NULL THEN
      RETURN true;
    END IF;
    RETURN public.profile_default_event_subscription(p_company_id, p_profile_id, v_event_id);
  END IF;

  IF public.profile_leads_department(p_profile_id, p_department_id) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

-- Godkjenning: alle med rolle leder + avdeling registreres som avdelingsleder
CREATE OR REPLACE FUNCTION public.approve_employee_profile(
  p_profile_id UUID,
  p_role public.user_role,
  p_department_id UUID,
  p_access_settings JSONB,
  p_set_department_leader BOOLEAN DEFAULT FALSE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  requester_role public.user_role;
  requester_company UUID;
  target_company UUID;
BEGIN
  requester_role := public.get_user_role();
  requester_company := public.get_user_company_id();

  IF requester_role IS DISTINCT FROM 'superadmin' THEN
    RAISE EXCEPTION 'Kun superadmin kan godkjenne nye ansatte';
  END IF;

  SELECT company_id INTO target_company FROM public.profiles WHERE id = p_profile_id;
  IF target_company IS NULL OR target_company IS DISTINCT FROM requester_company THEN
    RAISE EXCEPTION 'Bruker tilhører ikke ditt selskap';
  END IF;

  UPDATE public.profiles
  SET
    role = p_role,
    department_id = p_department_id,
    access_settings = COALESCE(p_access_settings, '{}'::JSONB),
    is_approved = TRUE,
    is_active = TRUE,
    is_onboarded = TRUE
  WHERE id = p_profile_id;

  IF p_department_id IS NOT NULL
     AND (
       p_set_department_leader
       OR p_role = 'leder'::public.user_role
     ) THEN
    INSERT INTO public.department_leaders (department_id, profile_id)
    VALUES (p_department_id, p_profile_id)
    ON CONFLICT DO NOTHING;

    UPDATE public.departments
    SET leader_id = COALESCE(leader_id, p_profile_id)
    WHERE id = p_department_id AND company_id = target_company;
  END IF;
END;
$$;

-- set_department_leaders: synkroniser også når listen er tom (tømmer leader_id)
CREATE OR REPLACE FUNCTION public.set_department_leaders(
  p_department_id UUID,
  p_leader_ids UUID[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID;
  v_primary UUID;
BEGIN
  IF public.get_user_role() NOT IN ('superadmin'::public.user_role, 'admin'::public.user_role) THEN
    RAISE EXCEPTION 'Kun admin/superadmin kan endre avdelingsledere';
  END IF;

  SELECT company_id INTO v_company FROM public.departments WHERE id = p_department_id;
  IF v_company IS NULL THEN
    RAISE EXCEPTION 'Ukjent avdeling';
  END IF;

  IF public.get_user_role() IS DISTINCT FROM 'superadmin'::public.user_role
     AND v_company IS DISTINCT FROM public.get_user_company_id() THEN
    RAISE EXCEPTION 'Avdeling tilhører ikke ditt selskap';
  END IF;

  DELETE FROM public.department_leaders WHERE department_id = p_department_id;

  IF p_leader_ids IS NOT NULL THEN
    INSERT INTO public.department_leaders (department_id, profile_id)
    SELECT p_department_id, unnest(p_leader_ids)
    ON CONFLICT DO NOTHING;
  END IF;

  SELECT dl.profile_id INTO v_primary
  FROM public.department_leaders dl
  WHERE dl.department_id = p_department_id
  ORDER BY dl.created_at
  LIMIT 1;

  UPDATE public.departments
  SET leader_id = v_primary
  WHERE id = p_department_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.profile_leads_department(uuid, uuid) TO authenticated;
