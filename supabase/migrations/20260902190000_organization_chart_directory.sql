-- Organisasjonskart: trygg bedriftskatalog (navn/tittel/avdeling) for alle innloggede i selskapet.
-- Full profil-GDPR forblir stram; dette er kun det som trengs for orgkart.

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
    p.job_title,
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
    AND p.role <> 'superadmin'::public.user_role
  ORDER BY p.full_name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_organization_chart() TO authenticated;

COMMENT ON FUNCTION public.get_organization_chart IS
  'Offentlig bedriftskatalog til organisasjonskart (navn, tittel, avdeling).';
