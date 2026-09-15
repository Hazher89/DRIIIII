-- Fix ambiguous full_name in get_work_steps_hub_overview (PL/pgSQL OUT vs column).

CREATE OR REPLACE FUNCTION public.get_work_steps_hub_overview(
  p_from DATE DEFAULT (CURRENT_DATE - 14),
  p_to DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
  profile_id UUID,
  full_name TEXT,
  employee_number TEXT,
  consent_enabled BOOLEAN,
  steps_today INT,
  steps_period INT,
  days_with_data INT,
  last_synced_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_company UUID := public.get_user_company_id();
BEGIN
  IF auth.uid() IS NULL OR v_company IS NULL THEN
    RETURN;
  END IF;

  IF NOT (
    public.is_company_admin()
    OR public.get_user_role() IN (
      'admin'::public.user_role,
      'superadmin'::public.user_role,
      'leder'::public.user_role
    )
    OR public.profile_has_access(auth.uid(), 'more.work_steps_hub', 'view')
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang til skritt-oversikt';
  END IF;

  RETURN QUERY
  SELECT
    p.id AS profile_id,
    coalesce(nullif(trim(p.full_name), ''), p.email, 'Ukjent')::text AS full_name,
    nullif(trim(p.employee_number), '')::text AS employee_number,
    coalesce(c.enabled, false) AS consent_enabled,
    coalesce((
      SELECT d.steps_at_work
      FROM public.employee_work_steps_daily d
      WHERE d.profile_id = p.id AND d.work_date = CURRENT_DATE
    ), 0)::int AS steps_today,
    coalesce((
      SELECT sum(d.steps_at_work)::int
      FROM public.employee_work_steps_daily d
      WHERE d.profile_id = p.id
        AND d.work_date BETWEEN p_from AND p_to
    ), 0) AS steps_period,
    coalesce((
      SELECT count(*)::int
      FROM public.employee_work_steps_daily d
      WHERE d.profile_id = p.id
        AND d.work_date BETWEEN p_from AND p_to
        AND d.steps_at_work > 0
    ), 0) AS days_with_data,
    (
      SELECT max(d.synced_at)
      FROM public.employee_work_steps_daily d
      WHERE d.profile_id = p.id
    ) AS last_synced_at
  FROM public.profiles p
  LEFT JOIN public.employee_work_steps_consent c ON c.profile_id = p.id
  WHERE p.company_id = v_company
    AND coalesce(p.is_active, true)
    AND p.role IS DISTINCT FROM 'samarbeidspartner'::public.user_role
    AND p.partner_id IS NULL
  ORDER BY coalesce(c.enabled, false) DESC,
           coalesce(nullif(trim(p.full_name), ''), p.email, 'Ukjent');
END;
$$;
