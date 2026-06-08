-- Ansatt kan ikke lese alle profiler (GDPR) → tom saksbehandler-liste og grå «Send avvik».
-- SECURITY DEFINER RPC returnerer kun ledere/superadmin som kan motta avvik.

DROP POLICY IF EXISTS profiles_select_own ON public.profiles;
CREATE POLICY profiles_select_own ON public.profiles
  FOR SELECT TO authenticated
  USING (id = auth.uid());

DROP POLICY IF EXISTS profiles_select_superadmin ON public.profiles;
CREATE POLICY profiles_select_superadmin ON public.profiles
  FOR SELECT TO authenticated
  USING (
    public.get_user_role() = 'superadmin'::public.user_role
    AND company_id IS NOT NULL
    AND company_id = public.get_user_company_id()
  );

CREATE OR REPLACE FUNCTION public._ticket_assignee_profile_json(p public.profiles)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'id', p.id,
    'email', COALESCE(p.email, ''),
    'full_name', COALESCE(p.full_name, 'Bruker'),
    'role', p.role,
    'department_id', p.department_id,
    'company_id', p.company_id,
    'is_active', COALESCE(p.is_active, true),
    'is_approved', COALESCE(p.is_approved, false)
  );
$$;

CREATE OR REPLACE FUNCTION public.get_ticket_assignee_options(
  p_department_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_dept_id uuid;
  v_nearest_ids uuid[] := ARRAY[]::uuid[];
  v_all_leader_ids uuid[] := ARRAY[]::uuid[];
  v_nearest jsonb := '[]'::jsonb;
  v_other jsonb := '[]'::jsonb;
  v_super jsonb := '[]'::jsonb;
  v_row public.profiles%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object(
      'nearest_leaders', '[]'::jsonb,
      'other_leaders', '[]'::jsonb,
      'superadmins', '[]'::jsonb
    );
  END IF;

  SELECT company_id, COALESCE(p_department_id, department_id)
  INTO v_company_id, v_dept_id
  FROM public.profiles
  WHERE id = auth.uid();

  IF v_company_id IS NULL THEN
    RETURN jsonb_build_object(
      'nearest_leaders', '[]'::jsonb,
      'other_leaders', '[]'::jsonb,
      'superadmins', '[]'::jsonb
    );
  END IF;

  IF v_dept_id IS NOT NULL THEN
    SELECT COALESCE(array_agg(DISTINCT lid), ARRAY[]::uuid[])
    INTO v_nearest_ids
    FROM (
      SELECT d.leader_id AS lid
      FROM public.departments d
      WHERE d.id = v_dept_id AND d.leader_id IS NOT NULL
      UNION
      SELECT dl.profile_id AS lid
      FROM public.department_leaders dl
      WHERE dl.department_id = v_dept_id
    ) src
    WHERE lid IS NOT NULL;

    IF COALESCE(cardinality(v_nearest_ids), 0) = 0 THEN
      SELECT COALESCE(array_agg(p.id ORDER BY p.full_name), ARRAY[]::uuid[])
      INTO v_nearest_ids
      FROM public.profiles p
      WHERE p.company_id = v_company_id
        AND p.department_id = v_dept_id
        AND p.role = 'leder'::public.user_role
        AND COALESCE(p.is_active, true)
        AND COALESCE(p.is_approved, false)
        AND p.partner_id IS NULL;
    END IF;
  END IF;

  SELECT COALESCE(array_agg(DISTINCT lid), ARRAY[]::uuid[])
  INTO v_all_leader_ids
  FROM (
    SELECT d.leader_id AS lid
    FROM public.departments d
    WHERE d.company_id = v_company_id AND d.leader_id IS NOT NULL
    UNION
    SELECT dl.profile_id AS lid
    FROM public.department_leaders dl
    JOIN public.departments d ON d.id = dl.department_id
    WHERE d.company_id = v_company_id
    UNION
    SELECT p.id AS lid
    FROM public.profiles p
    WHERE p.company_id = v_company_id
      AND p.role IN ('leder'::public.user_role, 'admin'::public.user_role)
      AND COALESCE(p.is_active, true)
      AND COALESCE(p.is_approved, false)
      AND p.partner_id IS NULL
  ) src
  WHERE lid IS NOT NULL;

  SELECT COALESCE(jsonb_agg(public._ticket_assignee_profile_json(p) ORDER BY p.full_name), '[]'::jsonb)
  INTO v_nearest
  FROM public.profiles p
  WHERE p.id = ANY (v_nearest_ids)
    AND p.company_id = v_company_id
    AND COALESCE(p.is_active, true)
    AND COALESCE(p.is_approved, false)
    AND p.partner_id IS NULL;

  SELECT COALESCE(jsonb_agg(public._ticket_assignee_profile_json(p) ORDER BY p.full_name), '[]'::jsonb)
  INTO v_other
  FROM public.profiles p
  WHERE p.id = ANY (v_all_leader_ids)
    AND NOT (p.id = ANY (v_nearest_ids))
    AND p.company_id = v_company_id
    AND COALESCE(p.is_active, true)
    AND COALESCE(p.is_approved, false)
    AND p.partner_id IS NULL;

  SELECT COALESCE(jsonb_agg(public._ticket_assignee_profile_json(p) ORDER BY p.full_name), '[]'::jsonb)
  INTO v_super
  FROM public.profiles p
  WHERE p.company_id = v_company_id
    AND p.role = 'superadmin'::public.user_role
    AND COALESCE(p.is_active, true)
    AND COALESCE(p.is_approved, false)
    AND p.partner_id IS NULL
    AND NOT (p.id = ANY (v_nearest_ids))
    AND NOT (p.id = ANY (v_all_leader_ids));

  RETURN jsonb_build_object(
    'nearest_leaders', v_nearest,
    'other_leaders', v_other,
    'superadmins', v_super
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_ticket_assignee_options(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_ticket_assignee_options(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_ticket_assignee_options(uuid) IS
  'Ledere/superadmin som ansatt kan velge ved avvik — uten full profil-liste (GDPR).';
