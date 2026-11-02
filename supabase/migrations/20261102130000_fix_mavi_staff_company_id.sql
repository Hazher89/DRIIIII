-- hazher@mavilogistikk.no (og andre MAVI-ansatte) hadde company_id = DriftPro Demo AS
-- mens alle partnere ligger under MAVI Logistikk → Bedrifter viste 0.

UPDATE public.profiles p
SET company_id = public.get_bootstrap_company_id()
WHERE public.get_bootstrap_company_id() IS NOT NULL
  AND p.partner_id IS NULL
  AND p.company_id IS DISTINCT FROM public.get_bootstrap_company_id()
  AND (
    lower(trim(coalesce(p.email, ''))) = 'hazher@mavilogistikk.no'
    OR lower(trim(coalesce(p.email, ''))) LIKE '%@mavilogistikk.no'
    OR lower(trim(coalesce(p.email, ''))) LIKE '%@mavi-employees.driftpro.no'
    OR trim(coalesce(p.employee_number, '')) = '25'
  );

-- Ved login: ikke behold feil/demo company for MAVI-ansatte (coalesce holdt Demo).
CREATE OR REPLACE FUNCTION public.restore_mavi_employee_profile(p_uid UUID DEFAULT auth.uid())
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  emp_no TEXT;
  cid UUID;
  dept_id UUID;
  ph TEXT;
  em TEXT;
  fn TEXT;
  target_role public.user_role;
  bootstrap UUID := public.get_bootstrap_company_id();
BEGIN
  IF p_uid IS NULL THEN
    RETURN;
  END IF;

  SELECT
    ela.employee_number,
    ela.company_id,
    ela.department_id,
    ela.phone,
    lower(trim(ela.login_email)),
    trim(coalesce(ela.first_name, '') || ' ' || coalesce(ela.last_name, ''))
  INTO emp_no, cid, dept_id, ph, em, fn
  FROM public.employee_login_accounts ela
  WHERE ela.is_active = true
    AND (
      ela.profile_id = p_uid
      OR lower(trim(ela.login_email)) = (
        SELECT lower(trim(p.email)) FROM public.profiles p WHERE p.id = p_uid
      )
    )
  ORDER BY CASE WHEN ela.profile_id = p_uid THEN 0 ELSE 1 END
  LIMIT 1;

  IF emp_no IS NULL THEN
    SELECT trim(coalesce(p.employee_number, '')), p.company_id, p.department_id,
           p.phone, lower(trim(coalesce(p.email, ''))), trim(coalesce(p.full_name, ''))
    INTO emp_no, cid, dept_id, ph, em, fn
    FROM public.profiles p
    WHERE p.id = p_uid
      AND (
        trim(coalesce(p.employee_number, '')) = '25'
        OR lower(trim(coalesce(p.email, ''))) LIKE '%@mavi-employees.driftpro.no'
        OR lower(trim(coalesce(p.email, ''))) LIKE '%@mavilogistikk.no'
      );
  END IF;

  -- Ren @mavilogistikk.no uten employee_login: fortsatt på bootstrap-selskap.
  IF emp_no IS NULL OR emp_no = '' THEN
    UPDATE public.profiles
    SET company_id = coalesce(bootstrap, company_id)
    WHERE id = p_uid
      AND partner_id IS NULL
      AND lower(trim(coalesce(email, ''))) LIKE '%@mavilogistikk.no'
      AND bootstrap IS NOT NULL
      AND company_id IS DISTINCT FROM bootstrap;
    RETURN;
  END IF;

  target_role := CASE
    WHEN trim(emp_no) = '25' THEN 'superadmin'::public.user_role
    ELSE 'ansatt'::public.user_role
  END;

  UPDATE public.partner_portal_accounts
  SET profile_id = NULL, updated_at = now()
  WHERE profile_id = p_uid
    AND is_active = true;

  UPDATE public.profiles
  SET
    email = coalesce(nullif(em, ''), email),
    full_name = CASE
      WHEN trim(emp_no) = '25' THEN 'Hazher'
      WHEN coalesce(fn, '') <> '' THEN fn
      ELSE full_name
    END,
    partner_id = NULL,
    partner_vehicle_id = NULL,
    employee_number = emp_no,
    company_id = coalesce(bootstrap, cid, company_id),
    department_id = coalesce(department_id, dept_id),
    phone = coalesce(ph, phone),
    role = target_role,
    is_active = true,
    is_approved = true,
    is_onboarded = true
  WHERE id = p_uid;

  UPDATE public.employee_login_accounts
  SET profile_id = p_uid, updated_at = now()
  WHERE is_active = true
    AND employee_number = emp_no
    AND (profile_id IS NULL OR profile_id = p_uid);
END;
$$;
