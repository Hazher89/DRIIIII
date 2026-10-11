-- Anonymt avvik skal alltid kunne sendes til Tommy, Nico og Hazher,
-- også når de ikke har rollen superadmin.

CREATE OR REPLACE FUNCTION public.get_ticket_assignee_options(
  p_department_id uuid DEFAULT NULL,
  p_profile_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_subject uuid;
  v_dept_id uuid;
  v_nearest_ids uuid[] := ARRAY[]::uuid[];
  v_nearest jsonb := '[]'::jsonb;
  v_super jsonb := '[]'::jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object(
      'nearest_leaders', '[]'::jsonb,
      'other_leaders', '[]'::jsonb,
      'superadmins', '[]'::jsonb
    );
  END IF;

  v_subject := coalesce(p_profile_id, auth.uid());

  SELECT company_id, COALESCE(p_department_id, department_id)
  INTO v_company_id, v_dept_id
  FROM public.profiles
  WHERE id = v_subject;

  IF v_company_id IS NULL THEN
    SELECT company_id INTO v_company_id
    FROM public.profiles
    WHERE id = auth.uid();
  END IF;

  IF v_company_id IS NULL THEN
    RETURN jsonb_build_object(
      'nearest_leaders', '[]'::jsonb,
      'other_leaders', '[]'::jsonb,
      'superadmins', '[]'::jsonb
    );
  END IF;

  IF to_regprocedure('public.profile_manager_ids(uuid)') IS NOT NULL THEN
    v_nearest_ids := public.profile_manager_ids(v_subject);
  ELSIF v_dept_id IS NOT NULL THEN
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
    WHERE lid IS NOT NULL
      AND lid IS DISTINCT FROM v_subject;
  END IF;

  SELECT COALESCE(jsonb_agg(public._ticket_assignee_profile_json(pr) ORDER BY pr.full_name), '[]'::jsonb)
  INTO v_nearest
  FROM public.profiles pr
  WHERE pr.id = ANY (v_nearest_ids)
    AND pr.company_id = v_company_id
    AND pr.id IS DISTINCT FROM v_subject
    AND COALESCE(pr.is_active, true)
    AND COALESCE(pr.is_approved, false)
    AND pr.partner_id IS NULL;

  SELECT COALESCE(jsonb_agg(public._ticket_assignee_profile_json(pr) ORDER BY
    CASE
      WHEN coalesce(pr.employee_number, '') = '100' OR lower(pr.full_name) LIKE '%tommy%' THEN 0
      WHEN coalesce(pr.employee_number, '') = '144' OR lower(pr.full_name) LIKE '%nicola%' THEN 1
      ELSE 2
    END,
    pr.full_name
  ), '[]'::jsonb)
  INTO v_super
  FROM public.profiles pr
  WHERE pr.company_id = v_company_id
    AND pr.id IS DISTINCT FROM v_subject
    AND COALESCE(pr.is_active, true)
    AND COALESCE(pr.is_approved, false)
    AND pr.partner_id IS NULL
    AND public.profile_is_company_principal(pr);

  RETURN jsonb_build_object(
    'nearest_leaders', v_nearest,
    'other_leaders', '[]'::jsonb,
    'superadmins', v_super
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_ticket_assignee_options(UUID, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
