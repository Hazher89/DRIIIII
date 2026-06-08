-- Ansattnummer-innlogging (@mavi-employees.driftpro.no) skal aldri bli samarbeidspartner.
-- Ansatt 25 (Hazher) skal være superadmin.

CREATE OR REPLACE FUNCTION public.is_mavi_employee_login_profile(p_uid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.employee_login_accounts ela
    WHERE ela.is_active = true
      AND (
        ela.profile_id = p_uid
        OR lower(trim(ela.login_email)) = (
          SELECT lower(trim(p.email)) FROM public.profiles p WHERE p.id = p_uid
        )
      )
  )
  OR EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = p_uid
      AND lower(trim(coalesce(p.email, ''))) LIKE '%@mavi-employees.driftpro.no'
  );
$$;

CREATE OR REPLACE FUNCTION public.restore_mavi_employee_profile(p_uid UUID DEFAULT auth.uid())
RETURNS VOID
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
    RETURN;
  END IF;

  target_role := CASE
    WHEN trim(emp_no) = '25' THEN 'superadmin'::public.user_role
    ELSE 'ansatt'::public.user_role
  END;

  UPDATE public.profiles
  SET
    email = coalesce(nullif(em, ''), email),
    full_name = CASE WHEN coalesce(fn, '') <> '' THEN fn ELSE full_name END,
    partner_id = NULL,
    partner_vehicle_id = NULL,
    employee_number = emp_no,
    company_id = coalesce(company_id, cid),
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

CREATE OR REPLACE FUNCTION public.apply_partner_bootstrap_to_profile()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  em TEXT := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  p UUID;
  c UUID;
  vid UUID;
  current_role public.user_role;
BEGIN
  IF uid IS NULL THEN
    RETURN;
  END IF;

  IF public.is_mavi_employee_login_profile(uid) THEN
    PERFORM public.restore_mavi_employee_profile(uid);
    RETURN;
  END IF;

  SELECT role INTO current_role FROM public.profiles WHERE id = uid;

  IF current_role IN ('superadmin', 'admin') THEN
    RETURN;
  END IF;

  IF em NOT LIKE '%@portal.driftpro.no'
     AND em NOT LIKE '%.portal'
     AND current_role IS DISTINCT FROM 'samarbeidspartner'::public.user_role THEN
    PERFORM public.clear_stale_partner_portal_profile(uid);
    RETURN;
  END IF;

  SELECT ppa.partner_id, ppa.company_id, ppa.partner_vehicle_id
  INTO p, c, vid
  FROM public.partner_portal_accounts ppa
  WHERE ppa.is_active = true
    AND (
      ppa.profile_id = uid
      OR (em <> '' AND lower(trim(ppa.login_email)) = em)
    )
  ORDER BY CASE WHEN ppa.profile_id = uid THEN 0 ELSE 1 END
  LIMIT 1;

  IF p IS NULL THEN
    PERFORM public.clear_stale_partner_portal_profile(uid);
    RETURN;
  END IF;

  UPDATE public.profiles
  SET
    partner_id = p,
    company_id = coalesce(company_id, c),
    partner_vehicle_id = vid,
    role = 'samarbeidspartner'::public.user_role,
    is_onboarded = true,
    is_approved = true,
    is_active = true
  WHERE id = uid;
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_internal_profile_missing()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  em TEXT := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  default_company_id UUID;
  is_super BOOLEAN;
  fn TEXT;
BEGIN
  IF uid IS NULL OR em = '' THEN
    RETURN;
  END IF;

  IF em LIKE '%.portal' OR em LIKE '%@portal.driftpro.no' THEN
    RETURN;
  END IF;

  IF public.is_mavi_employee_login_profile(uid) THEN
    PERFORM public.restore_mavi_employee_profile(uid);
    RETURN;
  END IF;

  SELECT id INTO default_company_id FROM public.companies LIMIT 1;

  is_super := em IN (
    'baxigshti@gmail.com',
    'baxightsi@gmail.com',
    'baxigshti@hotmail.de',
    'baxlgshtl@gmail.com',
    'hazher@mavilogistikk.no'
  );

  fn := coalesce(nullif(trim(split_part(em, '@', 1)), ''), 'Bruker');

  IF EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = uid) THEN
    IF is_super THEN
      UPDATE public.profiles
      SET
        email = em,
        role = 'superadmin'::public.user_role,
        partner_id = NULL,
        partner_vehicle_id = NULL,
        is_onboarded = TRUE,
        is_approved = TRUE,
        is_active = TRUE,
        company_id = coalesce(company_id, default_company_id)
      WHERE id = uid;
    END IF;
    RETURN;
  END IF;

  INSERT INTO public.profiles (
    id, email, full_name, company_id, role, access_settings,
    is_onboarded, is_approved, is_active
  )
  VALUES (
    uid, em, fn, default_company_id,
    CASE WHEN is_super THEN 'superadmin'::public.user_role ELSE 'ansatt'::public.user_role END,
    '{}'::JSONB,
    CASE WHEN is_super THEN TRUE ELSE FALSE END,
    CASE WHEN is_super THEN TRUE ELSE FALSE END,
    TRUE
  )
  ON CONFLICT (id) DO NOTHING;
END;
$$;

-- Engangs-reparasjon: ansatt 25 + alle mavi-employees med feil rolle.
UPDATE public.profiles p
SET
  role = CASE WHEN trim(coalesce(p.employee_number, ela.employee_number, '')) = '25'
    THEN 'superadmin'::public.user_role
    ELSE 'ansatt'::public.user_role
  END,
  partner_id = NULL,
  partner_vehicle_id = NULL,
  employee_number = coalesce(p.employee_number, ela.employee_number),
  is_active = true,
  is_approved = true,
  is_onboarded = true
FROM public.employee_login_accounts ela
WHERE ela.is_active = true
  AND (
    ela.profile_id = p.id
    OR lower(trim(ela.login_email)) = lower(trim(p.email))
  )
  AND (
    p.role = 'samarbeidspartner'::public.user_role
    OR p.partner_id IS NOT NULL
    OR p.partner_vehicle_id IS NOT NULL
  );

GRANT EXECUTE ON FUNCTION public.is_mavi_employee_login_profile(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.restore_mavi_employee_profile(UUID) TO authenticated, service_role;