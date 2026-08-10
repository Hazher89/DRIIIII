-- Ansattnummer-innlogging (spesielt #25 / Hazher) skal aldri blandes med partnerportal.
-- Løser: samme person har både MAVI-ansatt og bedrift som samarbeidspartner.

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
      AND (
        lower(trim(coalesce(p.email, ''))) LIKE '%@mavi-employees.driftpro.no'
        OR trim(coalesce(p.employee_number, '')) = '25'
      )
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

  -- Fallback: profil allerede merket med ansattnummer 25
  IF emp_no IS NULL THEN
    SELECT trim(coalesce(p.employee_number, '')), p.company_id, p.department_id,
           p.phone, lower(trim(coalesce(p.email, ''))), trim(coalesce(p.full_name, ''))
    INTO emp_no, cid, dept_id, ph, em, fn
    FROM public.profiles p
    WHERE p.id = p_uid
      AND (
        trim(coalesce(p.employee_number, '')) = '25'
        OR lower(trim(coalesce(p.email, ''))) LIKE '%@mavi-employees.driftpro.no'
      );
  END IF;

  IF emp_no IS NULL OR emp_no = '' THEN
    RETURN;
  END IF;

  target_role := CASE
    WHEN trim(emp_no) = '25' THEN 'superadmin'::public.user_role
    ELSE 'ansatt'::public.user_role
  END;

  -- Koble profilen løs fra partnerportal (behold portal-kontoen for egen innlogging).
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

-- Engangs-reparasjon: løsne alle MAVI-ansattprofiler fra partnerportal + sett #25 til superadmin.
UPDATE public.partner_portal_accounts ppa
SET profile_id = NULL, updated_at = now()
WHERE profile_id IS NOT NULL
  AND public.is_mavi_employee_login_profile(ppa.profile_id);

UPDATE public.profiles p
SET
  role = CASE
    WHEN trim(coalesce(p.employee_number, ela.employee_number, '')) = '25'
      THEN 'superadmin'::public.user_role
    WHEN p.role IN ('superadmin'::public.user_role, 'admin'::public.user_role)
      THEN p.role
    ELSE 'ansatt'::public.user_role
  END,
  full_name = CASE
    WHEN trim(coalesce(p.employee_number, ela.employee_number, '')) = '25'
      THEN 'Hazher'
    ELSE p.full_name
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
  );

-- Explicit: ansatt 25 alltid superadmin (også uten join-treff).
UPDATE public.profiles
SET
  role = 'superadmin'::public.user_role,
  full_name = 'Hazher',
  partner_id = NULL,
  partner_vehicle_id = NULL,
  is_active = true,
  is_approved = true,
  is_onboarded = true
WHERE trim(coalesce(employee_number, '')) = '25'
   OR lower(trim(coalesce(email, ''))) = 'e25@mavi-employees.driftpro.no';

GRANT EXECUTE ON FUNCTION public.is_mavi_employee_login_profile(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.restore_mavi_employee_profile(UUID) TO authenticated, service_role;
