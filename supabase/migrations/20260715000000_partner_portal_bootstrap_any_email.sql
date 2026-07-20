-- Partner-portal: bootstrap skal fungere for alle login_email i partner_portal_accounts,
-- ikke bare adresser som ender på .portal / @portal.driftpro.no.

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
    IF em NOT LIKE '%@portal.driftpro.no'
       AND em NOT LIKE '%.portal'
       AND current_role IS DISTINCT FROM 'samarbeidspartner'::public.user_role THEN
      PERFORM public.clear_stale_partner_portal_profile(uid);
    END IF;
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

  UPDATE public.partner_portal_accounts
  SET profile_id = uid, updated_at = now()
  WHERE is_active = true
    AND lower(trim(login_email)) = em
    AND (profile_id IS NULL OR profile_id = uid);
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_partner_profile_from_portal()
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
  fn TEXT;
  ph TEXT;
  row_email TEXT;
  final_email TEXT;
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

  SELECT
    ppa.partner_id,
    ppa.company_id,
    ppa.partner_vehicle_id,
    ppa.phone,
    lower(trim(ppa.login_email))
  INTO p, c, vid, ph, row_email
  FROM public.partner_portal_accounts ppa
  WHERE ppa.is_active = true
    AND (
      ppa.profile_id = uid
      OR (em <> '' AND lower(trim(ppa.login_email)) = em)
    )
  ORDER BY CASE WHEN ppa.profile_id = uid THEN 0 ELSE 1 END
  LIMIT 1;

  IF p IS NULL THEN
    RETURN;
  END IF;

  final_email := lower(trim(coalesce(nullif(em, ''), row_email, '')));
  IF final_email = '' THEN
    RETURN;
  END IF;

  fn := coalesce(nullif(trim(split_part(final_email, '@', 1)), ''), 'Partner');

  INSERT INTO public.profiles (
    id,
    email,
    full_name,
    role,
    company_id,
    partner_id,
    partner_vehicle_id,
    phone,
    is_onboarded,
    is_approved,
    is_active
  )
  VALUES (
    uid,
    final_email,
    fn,
    'samarbeidspartner'::public.user_role,
    c,
    p,
    vid,
    ph,
    true,
    true,
    true
  )
  ON CONFLICT (id) DO UPDATE SET
    email = excluded.email,
    partner_id = excluded.partner_id,
    company_id = coalesce(public.profiles.company_id, excluded.company_id),
    partner_vehicle_id = excluded.partner_vehicle_id,
    phone = coalesce(excluded.phone, public.profiles.phone),
    role = 'samarbeidspartner'::public.user_role,
    is_onboarded = true,
    is_approved = true,
    is_active = true;

  UPDATE public.partner_portal_accounts
  SET profile_id = uid, updated_at = now()
  WHERE is_active = true
    AND lower(trim(login_email)) = final_email
    AND (profile_id IS NULL OR profile_id = uid);
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

  IF EXISTS (
    SELECT 1
    FROM public.partner_portal_accounts ppa
    WHERE ppa.is_active = true
      AND (
        ppa.profile_id = uid
        OR lower(trim(ppa.login_email)) = em
      )
  ) THEN
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
