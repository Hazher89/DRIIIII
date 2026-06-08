-- Ikke nedgrader superadmin/admin til samarbeidspartner ved portal-bootstrap.

CREATE OR REPLACE FUNCTION public.is_internal_mavi_profile(p_uid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = p_uid
      AND p.role IN ('superadmin', 'admin', 'leder', 'ansatt')
      AND (
        p.role IN ('superadmin', 'admin')
        OR lower(trim(coalesce(p.email, ''))) NOT LIKE '%@portal.driftpro.no'
        AND lower(trim(coalesce(p.email, ''))) NOT LIKE '%.portal'
      )
  );
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

  SELECT role INTO current_role FROM public.profiles WHERE id = uid;
  IF current_role IN ('superadmin', 'admin') THEN
    RETURN;
  END IF;

  IF em NOT LIKE '%@portal.driftpro.no'
     AND em NOT LIKE '%.portal'
     AND current_role IS DISTINCT FROM 'samarbeidspartner'::public.user_role THEN
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
END;
$$;

-- Gjenopprett superadmin som ble nedgradert ved portal-testing.
UPDATE public.profiles
SET
  role = 'superadmin',
  partner_id = NULL,
  partner_vehicle_id = NULL,
  is_active = true,
  is_approved = true,
  is_onboarded = true
WHERE lower(trim(email)) IN (
  'baxigshti@gmail.com',
  'baxightsi@gmail.com',
  'baxigshti@hotmail.de',
  'baxlgshtl@gmail.com'
)
AND role = 'samarbeidspartner'::public.user_role;

GRANT EXECUTE ON FUNCTION public.is_internal_mavi_profile(UUID) TO authenticated, service_role;
