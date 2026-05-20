-- ============================================================
-- KJØR DENNE på eksisterende Supabase (innlogging + data)
-- ============================================================
-- IKKE kjør schema.sql her — den gir «type user_role already exists».
-- Denne filen oppretter IKKE enum-typer eller tabeller på nytt.
-- Etter «Success»: logg ut og inn i appen.

-- ── 1. Selskap (minst ett) ─────────────────────────────────────────────────
INSERT INTO public.companies (id, name, org_number)
VALUES ('00000000-0000-0000-0000-000000000000', 'DriftPro Demo Selskap', '999999999')
ON CONFLICT (id) DO NOTHING;

-- ── 2. RLS-hjelpere (samme signatur som schema — unngår 42P13) ─────────────
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS public.user_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_user_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT company_id FROM public.profiles WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_bootstrap_company_id()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company uuid;
BEGIN
  SELECT d.company_id
  INTO v_company
  FROM public.departments d
  WHERE d.company_id IS NOT NULL
  GROUP BY d.company_id
  ORDER BY count(*) DESC
  LIMIT 1;

  IF v_company IS NOT NULL THEN
    RETURN v_company;
  END IF;

  SELECT c.id INTO v_company
  FROM public.companies c
  ORDER BY c.created_at ASC
  LIMIT 1;

  RETURN v_company;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_bootstrap_company_id() TO authenticated;

-- ── 3. Intern profil ved innlogging (SECURITY DEFINER) ─────────────────────
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

  IF em LIKE '%.portal' THEN
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

GRANT EXECUTE ON FUNCTION public.ensure_internal_profile_missing() TO authenticated;

-- ── 4. Eksisterende superadmin-kontoer ─────────────────────────────────────
UPDATE public.profiles
SET
  role = 'superadmin'::public.user_role,
  is_approved = TRUE,
  is_onboarded = TRUE,
  is_active = TRUE,
  company_id = coalesce(company_id, (SELECT id FROM public.companies LIMIT 1))
WHERE lower(email) IN (
  'baxigshti@gmail.com',
  'baxightsi@gmail.com',
  'baxigshti@hotmail.de',
  'baxlgshtl@gmail.com'
);

-- Alle uten selskap
UPDATE public.profiles
SET company_id = (SELECT id FROM public.companies LIMIT 1)
WHERE company_id IS NULL AND partner_id IS NULL;

-- ── 5. Profiles RLS — unngå infinite recursion (42P17) ─────────────────────
-- (Full reset: se fix_profiles_rls_recursion.sql — denne er en minimal inline-versjon)

DO $$
DECLARE pol record;
BEGIN
  FOR pol IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'profiles'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.profiles', pol.policyname);
  END LOOP;
END $$;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY profiles_select_own ON public.profiles FOR SELECT TO authenticated
USING (id = auth.uid());

CREATE POLICY profiles_select_superadmin ON public.profiles FOR SELECT TO authenticated
USING (get_user_role() = 'superadmin'::public.user_role);

CREATE POLICY profiles_select_company ON public.profiles FOR SELECT TO authenticated
USING (
  get_user_role() IN ('admin'::public.user_role, 'leder'::public.user_role)
  AND company_id IS NOT NULL
  AND company_id = get_user_company_id()
);

CREATE POLICY profiles_update_own ON public.profiles FOR UPDATE TO authenticated
USING (id = auth.uid()) WITH CHECK (id = auth.uid());

CREATE POLICY profiles_update_admin ON public.profiles FOR UPDATE TO authenticated
USING (
  get_user_role() IN ('admin'::public.user_role, 'superadmin'::public.user_role)
  AND company_id = get_user_company_id()
)
WITH CHECK (
  get_user_role() IN ('admin'::public.user_role, 'superadmin'::public.user_role)
  AND company_id = get_user_company_id()
);
