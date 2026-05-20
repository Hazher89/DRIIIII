-- Kjør i Supabase SQL Editor (prod).
--
-- Problem: portal-RPCer matchet kun JWT-e-post mot partner_portal_accounts.login_email.
-- Da brukeren likevel er innlogget som riktig auth-bruker (profile_id = auth.uid()),
-- feilet opprettelse av profil og Flutter viste «Kunne ikke laste profilen».
--
-- Løsning: match også på partner_portal_accounts.profile_id = auth.uid(),
-- prioriter den treffet, og bruk login_email fra raden om JWT mangler e-post.

CREATE INDEX IF NOT EXISTS idx_partner_portal_accounts_profile_id
  ON public.partner_portal_accounts (profile_id)
  WHERE is_active = true AND profile_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.resolve_partner_portal_bootstrap()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  em TEXT := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  r JSONB;
BEGIN
  IF uid IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_build_object(
    'partner_id', ppa.partner_id,
    'company_id', ppa.company_id,
    'partner_vehicle_id', ppa.partner_vehicle_id,
    'account_kind', coalesce(
      ppa.account_kind,
      case when ppa.partner_vehicle_id is null then 'owner' else 'driver' end
    )
  )
  INTO r
  FROM public.partner_portal_accounts ppa
  WHERE ppa.is_active = true
    AND (
      ppa.profile_id = uid
      OR (em <> '' AND lower(trim(ppa.login_email)) = em)
    )
  ORDER BY CASE WHEN ppa.profile_id = uid THEN 0 ELSE 1 END
  LIMIT 1;

  RETURN r;
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
BEGIN
  IF uid IS NULL THEN
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
    RETURN;
  END IF;

  UPDATE public.profiles
  SET
    partner_id = p,
    company_id = coalesce(company_id, c),
    partner_vehicle_id = vid,
    role = 'samarbeidspartner'::public.user_role,
    is_onboarded = true,
    is_approved = true
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
BEGIN
  IF uid IS NULL THEN
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

GRANT EXECUTE ON FUNCTION public.resolve_partner_portal_bootstrap() TO authenticated;
GRANT EXECUTE ON FUNCTION public.apply_partner_bootstrap_to_profile() TO authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_partner_profile_from_portal() TO authenticated;
