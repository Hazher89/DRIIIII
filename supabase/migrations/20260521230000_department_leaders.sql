-- Flere avdelingsledere per avdeling (M:N).

CREATE TABLE IF NOT EXISTS public.department_leaders (
  department_id UUID NOT NULL REFERENCES public.departments(id) ON DELETE CASCADE,
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (department_id, profile_id)
);

CREATE INDEX IF NOT EXISTS idx_department_leaders_profile
  ON public.department_leaders(profile_id);

ALTER TABLE public.department_leaders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS department_leaders_select ON public.department_leaders;
CREATE POLICY department_leaders_select ON public.department_leaders
  FOR SELECT TO authenticated
  USING (
    department_id IN (
      SELECT d.id FROM public.departments d
      WHERE d.company_id = public.get_user_company_id()
    )
    OR public.get_user_role() = 'superadmin'::public.user_role
  );

DROP POLICY IF EXISTS department_leaders_manage ON public.department_leaders;
CREATE POLICY department_leaders_manage ON public.department_leaders
  FOR ALL TO authenticated
  USING (
    public.get_user_role() IN ('superadmin'::public.user_role, 'admin'::public.user_role)
    AND department_id IN (
      SELECT d.id FROM public.departments d
      WHERE d.company_id = public.get_user_company_id()
    )
  )
  WITH CHECK (
    public.get_user_role() IN ('superadmin'::public.user_role, 'admin'::public.user_role)
    AND department_id IN (
      SELECT d.id FROM public.departments d
      WHERE d.company_id = public.get_user_company_id()
    )
  );

-- Migrer eksisterende enkeltleder.
INSERT INTO public.department_leaders (department_id, profile_id)
SELECT d.id, d.leader_id
FROM public.departments d
WHERE d.leader_id IS NOT NULL
ON CONFLICT DO NOTHING;

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

GRANT EXECUTE ON FUNCTION public.set_department_leaders(UUID, UUID[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.add_department_leader(
  p_department_id UUID,
  p_profile_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.department_leaders (department_id, profile_id)
  VALUES (p_department_id, p_profile_id)
  ON CONFLICT DO NOTHING;

  UPDATE public.departments
  SET leader_id = COALESCE(leader_id, p_profile_id)
  WHERE id = p_department_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_department_leader(UUID, UUID) TO authenticated;

-- Godkjenning: leder legges til (ikke erstatter andre ledere).
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

  IF p_set_department_leader AND p_department_id IS NOT NULL AND p_role = 'leder' THEN
    INSERT INTO public.department_leaders (department_id, profile_id)
    VALUES (p_department_id, p_profile_id)
    ON CONFLICT DO NOTHING;

    UPDATE public.departments
    SET leader_id = COALESCE(leader_id, p_profile_id)
    WHERE id = p_department_id AND company_id = target_company;
  END IF;
END;
$$;

-- SMS ved nytt fravær: varsle alle avdelingsledere.
CREATE OR REPLACE FUNCTION public.queue_absence_request_sms(p_absence public.absences)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  emp_name TEXT;
  dept_name TEXT;
  leader_id UUID;
  leader_on_leave BOOLEAN := false;
  msg TEXT;
  type_label TEXT;
  notified BOOLEAN := false;
BEGIN
  IF NOT public.company_sms_enabled(p_absence.company_id, 'absence_request') THEN
    RETURN;
  END IF;

  SELECT COALESCE(full_name, 'Ansatt') INTO emp_name
  FROM public.profiles WHERE id = p_absence.user_id;

  SELECT d.name INTO dept_name
  FROM public.departments d
  WHERE d.id = p_absence.department_id;

  type_label := CASE p_absence.type::text
    WHEN 'ferie' THEN 'ferie'
    WHEN 'sykdom' THEN 'sykmelding/fravær'
    WHEN 'permisjon' THEN 'permisjon'
    ELSE COALESCE(p_absence.type::text, 'fravær')
  END;

  msg :=
    'Mavi: NY SØKNAD ' || upper(type_label) || '. '
    || emp_name
    || ' (' || COALESCE(dept_name, 'uten avdeling') || ') '
    || to_char(p_absence.start_date, 'DD.MM') || '-' || to_char(p_absence.end_date, 'DD.MM')
    || '. Status: venter godkjenning. Åpne DriftPro.';

  FOR leader_id IN
    SELECT dl.profile_id
    FROM public.department_leaders dl
    WHERE dl.department_id = p_absence.department_id
  LOOP
    leader_on_leave := false;
    SELECT EXISTS (
      SELECT 1 FROM public.absences a
      WHERE a.user_id = leader_id
        AND a.status = 'godkjent'
        AND a.start_date <= CURRENT_DATE
        AND a.end_date >= CURRENT_DATE
    ) INTO leader_on_leave;

    IF NOT leader_on_leave THEN
      PERFORM public.queue_sms_if_allowed(
        p_absence.company_id,
        leader_id,
        NULL,
        msg,
        'absence_request',
        'absences',
        p_absence.id,
        'absence_request'
      );
      notified := true;
    END IF;
  END LOOP;

  IF NOT notified THEN
    FOR leader_id IN
      SELECT id FROM public.profiles
      WHERE company_id = p_absence.company_id
        AND is_active = true
        AND is_approved = true
        AND role IN ('superadmin', 'admin')
        AND phone_normalized IS NOT NULL
    LOOP
      PERFORM public.queue_sms_if_allowed(
        p_absence.company_id,
        leader_id,
        NULL,
        msg,
        'absence_request',
        'absences',
        p_absence.id,
        'absence_request'
      );
    END LOOP;
  END IF;
END;
$$;
