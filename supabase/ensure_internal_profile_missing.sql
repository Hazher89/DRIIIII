-- Kjør i Supabase SQL Editor (prod/dev).
--
-- Interne/admin-brukere: oppretter profiles-rad via SECURITY DEFINER når den mangler.
-- Samarbeidspartner (@*.portal): hoppes over — bruk ensure_partner_profile_from_portal.
--
-- Oppdatert: superadmin-e-poster inkl. vanlig skrivefeil baxlgshtl@gmail.com (i/l).
-- Hvis rad finnes fra trigger som «ansatt», men e-post er superadmin → løft rolle.

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

  SELECT id INTO default_company_id FROM public.companies LIMIT 1;

  is_super := em IN (
    'baxigshti@gmail.com',
    'baxightsi@gmail.com',
    'baxigshti@hotmail.de',
    'baxlgshtl@gmail.com'
  );

  fn := coalesce(nullif(trim(split_part(em, '@', 1)), ''), 'Bruker');

  IF EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = uid) THEN
    IF is_super THEN
      UPDATE public.profiles
      SET
        email = em,
        role = 'superadmin'::public.user_role,
        is_onboarded = TRUE,
        is_approved = TRUE,
        is_active = TRUE,
        company_id = coalesce(company_id, default_company_id)
      WHERE id = uid;
    END IF;
    RETURN;
  END IF;

  INSERT INTO public.profiles (
    id,
    email,
    full_name,
    company_id,
    role,
    access_settings,
    is_onboarded,
    is_approved,
    is_active
  )
  VALUES (
    uid,
    em,
    fn,
    default_company_id,
    CASE WHEN is_super THEN 'superadmin'::public.user_role ELSE 'ansatt'::public.user_role END,
    '{}'::JSONB,
    CASE WHEN is_super THEN TRUE ELSE FALSE END,
    CASE WHEN is_super THEN TRUE ELSE FALSE END,
    TRUE
  )
  ON CONFLICT (id) DO NOTHING;

END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_internal_profile_missing() TO authenticated;
