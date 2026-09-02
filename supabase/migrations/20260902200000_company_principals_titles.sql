-- Faste titler for Tommy / Nico / Hazher + inkluder dem i orgkart-RPC.

UPDATE public.profiles
SET
  full_name = 'Tommy Larsen',
  job_title = 'Daglig leder & medeier'
WHERE coalesce(employee_number, '') = '100'
   OR (
     lower(coalesce(full_name, '')) LIKE '%tommy%'
     AND role IN (
       'superadmin'::public.user_role,
       'admin'::public.user_role,
       'leder'::public.user_role
     )
   );

UPDATE public.profiles
SET
  full_name = 'Nicola Vino',
  job_title = 'Medeier'
WHERE coalesce(employee_number, '') = '144'
   OR (
     (
       lower(coalesce(full_name, '')) LIKE '%nicola%'
       OR lower(coalesce(full_name, '')) LIKE '%nico %'
       OR lower(coalesce(full_name, '')) = 'nico'
     )
     AND role IN (
       'superadmin'::public.user_role,
       'admin'::public.user_role,
       'leder'::public.user_role
     )
   );

UPDATE public.profiles
SET
  full_name = 'Hazher Abdullah',
  job_title = 'Driftsleder'
WHERE coalesce(employee_number, '') = '25'
   OR lower(coalesce(email, '')) LIKE '%hazher%'
   OR lower(coalesce(email, '')) LIKE '%baxigshti%'
   OR lower(coalesce(email, '')) LIKE '%baxightsi%'
   OR lower(coalesce(email, '')) LIKE '%baxlgshtl%'
   OR (
     lower(coalesce(full_name, '')) LIKE '%hazher%'
     AND role IN (
       'superadmin'::public.user_role,
       'admin'::public.user_role,
       'leder'::public.user_role
     )
   );

CREATE OR REPLACE FUNCTION public.get_organization_chart()
RETURNS TABLE (
  id uuid,
  full_name text,
  job_title text,
  department_id uuid,
  role public.user_role,
  employee_number text,
  is_active boolean,
  is_approved boolean,
  avatar_url text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company uuid := public.get_user_company_id();
BEGIN
  IF v_company IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.full_name,
    CASE
      WHEN coalesce(p.employee_number, '') = '100'
        OR lower(p.full_name) LIKE '%tommy%' THEN 'Daglig leder & medeier'
      WHEN coalesce(p.employee_number, '') = '144'
        OR lower(p.full_name) LIKE '%nicola%'
        OR lower(p.full_name) = 'nico'
        OR lower(p.full_name) LIKE 'nico %' THEN 'Medeier'
      WHEN coalesce(p.employee_number, '') = '25'
        OR lower(p.full_name) LIKE '%hazher%'
        OR lower(coalesce(p.email, '')) LIKE '%hazher%'
        OR lower(coalesce(p.email, '')) LIKE '%baxigshti%' THEN 'Driftsleder'
      ELSE p.job_title
    END AS job_title,
    p.department_id,
    p.role,
    p.employee_number,
    coalesce(p.is_active, true),
    coalesce(p.is_approved, false),
    p.avatar_url
  FROM public.profiles p
  WHERE p.company_id = v_company
    AND coalesce(p.is_active, true) = true
    AND coalesce(p.is_approved, false) = true
    AND p.partner_id IS NULL
    AND p.role <> 'samarbeidspartner'::public.user_role
    AND (
      p.role <> 'superadmin'::public.user_role
      OR coalesce(p.employee_number, '') IN ('25', '100', '144')
      OR lower(p.full_name) LIKE '%tommy%'
      OR lower(p.full_name) LIKE '%nicola%'
      OR lower(p.full_name) LIKE '%nico%'
      OR lower(p.full_name) LIKE '%hazher%'
      OR lower(coalesce(p.email, '')) LIKE '%hazher%'
      OR lower(coalesce(p.email, '')) LIKE '%baxigshti%'
      OR lower(coalesce(p.email, '')) LIKE '%tommy%'
      OR lower(coalesce(p.email, '')) LIKE '%nico%'
    )
  ORDER BY p.full_name;
END;
$$;

COMMENT ON FUNCTION public.get_organization_chart IS
  'Orgkart-katalog: inkluderer Tommy/Nico/Hazher med faste titler (ikke admin/superadmin).';
