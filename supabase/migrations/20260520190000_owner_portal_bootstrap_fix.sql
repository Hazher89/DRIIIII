-- Bil-eier: tving partner_vehicle_id = NULL og account_kind = owner i profil/bootstrap.

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
  kind TEXT;
BEGIN
  IF uid IS NULL THEN
    RETURN;
  END IF;

  SELECT
    ppa.partner_id,
    ppa.company_id,
    CASE
      WHEN coalesce(ppa.account_kind, CASE WHEN ppa.partner_vehicle_id IS NULL THEN 'owner' ELSE 'driver' END) = 'owner'
        THEN NULL::uuid
      ELSE ppa.partner_vehicle_id
    END,
    coalesce(ppa.account_kind, CASE WHEN ppa.partner_vehicle_id IS NULL THEN 'owner' ELSE 'driver' END)
  INTO p, c, vid, kind
  FROM public.partner_portal_accounts ppa
  WHERE ppa.is_active = true
    AND (
      ppa.profile_id = uid
      OR (em <> '' AND lower(trim(ppa.login_email)) = em)
      OR (em <> '' AND lower(trim(ppa.username)) = lower(trim(split_part(em, '@', 1))))
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
  row_username TEXT;
  final_email TEXT;
  kind TEXT;
BEGIN
  IF uid IS NULL THEN
    RETURN;
  END IF;

  SELECT
    ppa.partner_id,
    ppa.company_id,
    CASE
      WHEN coalesce(ppa.account_kind, CASE WHEN ppa.partner_vehicle_id IS NULL THEN 'owner' ELSE 'driver' END) = 'owner'
        THEN NULL::uuid
      ELSE ppa.partner_vehicle_id
    END,
    ppa.phone,
    lower(trim(ppa.login_email)),
    lower(trim(ppa.username)),
    coalesce(ppa.account_kind, CASE WHEN ppa.partner_vehicle_id IS NULL THEN 'owner' ELSE 'driver' END)
  INTO p, c, vid, ph, row_email, row_username, kind
  FROM public.partner_portal_accounts ppa
  WHERE ppa.is_active = true
    AND (
      ppa.profile_id = uid
      OR (em <> '' AND lower(trim(ppa.login_email)) = em)
      OR (em <> '' AND lower(trim(ppa.username)) = lower(trim(split_part(em, '@', 1))))
    )
  ORDER BY CASE WHEN ppa.profile_id = uid THEN 0 ELSE 1 END
  LIMIT 1;

  IF p IS NULL THEN
    RETURN;
  END IF;

  final_email := lower(trim(coalesce(nullif(em, ''), row_email, '')));
  IF final_email = '' AND row_username <> '' THEN
    final_email := row_username || '@portal.driftpro.no';
  END IF;
  IF final_email = '' THEN
    RETURN;
  END IF;

  fn := coalesce(nullif(trim(row_username), ''), nullif(trim(split_part(final_email, '@', 1)), ''), 'Partner');

  INSERT INTO public.profiles (
    id, email, full_name, role, company_id, partner_id, partner_vehicle_id,
    phone, is_onboarded, is_approved, is_active
  )
  VALUES (
    uid, final_email, fn, 'samarbeidspartner'::public.user_role,
    c, p, vid, ph, true, true, true
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
