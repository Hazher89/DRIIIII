-- Partner portal: profil-kobling, GDPR RLS, sjåfør kun egen bil/fri, rute-kvittering.

-- ── Bootstrap / profil fra partner_portal_accounts ─────────────────────────
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
      OR (em <> '' AND lower(trim(ppa.username)) = lower(trim(split_part(em, '@', 1))))
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
  row_username TEXT;
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
    lower(trim(ppa.login_email)),
    lower(trim(ppa.username))
  INTO p, c, vid, ph, row_email, row_username
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

GRANT EXECUTE ON FUNCTION public.resolve_partner_portal_bootstrap() TO authenticated;
GRANT EXECUTE ON FUNCTION public.apply_partner_bootstrap_to_profile() TO authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_partner_profile_from_portal() TO authenticated;

-- ── Ruter: sjåfør kun egen bil, bil-eier alle ────────────────────────────────
DROP POLICY IF EXISTS "partner_route_shares_select" ON public.partner_route_shares;
CREATE POLICY "partner_route_shares_select" ON public.partner_route_shares FOR SELECT USING (
  (
    company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_id IS NOT NULL AND p.partner_vehicle_id IS NULL
    )
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
    AND partner_vehicle_id IN (
      SELECT p.partner_vehicle_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
  )
);

DROP POLICY IF EXISTS "partner_route_shares_update" ON public.partner_route_shares;
CREATE POLICY "partner_route_shares_update" ON public.partner_route_shares FOR UPDATE USING (
  (
    company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_id IS NOT NULL AND p.partner_vehicle_id IS NULL
    )
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
    AND partner_vehicle_id IN (
      SELECT p.partner_vehicle_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
  )
);

-- ── Dokumenter ───────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "partner_documents_select" ON public.partner_documents;
CREATE POLICY "partner_documents_select" ON public.partner_documents FOR SELECT USING (
  (
    company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_id IS NOT NULL AND p.partner_vehicle_id IS NULL
    )
    AND COALESCE(owner_visible, true) = true
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
    AND COALESCE(driver_visible, false) = true
  )
);

-- ── Møter (bil-eier) ─────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "partner_meetings_select" ON public.partner_meetings;
CREATE POLICY "partner_meetings_select" ON public.partner_meetings FOR SELECT USING (
  partner_id IN (
    SELECT pr.id FROM public.partners pr
    WHERE pr.company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid())
  )
  OR partner_id IN (
    SELECT p.partner_id FROM public.profiles p
    WHERE p.id = auth.uid() AND p.partner_id IS NOT NULL AND p.partner_vehicle_id IS NULL
  )
);

-- ── Bilkontroll (bil-eier) ───────────────────────────────────────────────────
DROP POLICY IF EXISTS pvi_select ON public.partner_vehicle_inspections;
CREATE POLICY pvi_select ON public.partner_vehicle_inspections FOR SELECT USING (
  (
    company_id IN (SELECT p.company_id FROM public.profiles p WHERE p.id = auth.uid())
    AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
  )
  OR partner_id IN (
    SELECT p.partner_id FROM public.profiles p
    WHERE p.id = auth.uid() AND p.partner_id IS NOT NULL AND p.partner_vehicle_id IS NULL
  )
);

-- ── Partnere / kjøretøy ──────────────────────────────────────────────────────
DROP POLICY IF EXISTS "partners_select" ON public.partners;
CREATE POLICY "partners_select" ON public.partners FOR SELECT USING (
  company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
  OR id IN (SELECT partner_id FROM public.profiles WHERE id = auth.uid() AND partner_id IS NOT NULL)
);

DROP POLICY IF EXISTS "partner_vehicles_select" ON public.partner_vehicles;
CREATE POLICY "partner_vehicles_select" ON public.partner_vehicles FOR SELECT USING (
  (
    company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NULL AND p.partner_id IS NOT NULL
    )
  )
  OR id IN (
    SELECT p.partner_vehicle_id FROM public.profiles p
    WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
  )
);

-- ── Fri: sjåfør kun egne forespørsler ───────────────────────────────────────
DROP POLICY IF EXISTS "partner_fri_select" ON public.partner_fri_requests;
CREATE POLICY "partner_fri_select" ON public.partner_fri_requests FOR SELECT USING (
  (
    company_id IN (SELECT p.company_id FROM public.profiles p WHERE p.id = auth.uid())
    AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NULL AND p.partner_id IS NOT NULL
    )
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
    AND partner_vehicle_id IN (
      SELECT p.partner_vehicle_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
  )
);
