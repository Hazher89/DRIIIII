-- Fiks: infinite recursion detected in policy for relation "profiles" (42P17)
-- Årsak: policies som SELECT-er fra profiles inne i profiles-policy
--        (f.eks. final_fix.sql / final_security_lock.sql).
--
-- Kjør HELE filen i Supabase SQL Editor, deretter hard refresh / logg ut-inn.

-- ── 1. Hjelpere MÅ bypassa RLS (SECURITY DEFINER) ─────────────────────────
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

CREATE OR REPLACE FUNCTION public.get_user_department_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT department_id FROM public.profiles WHERE id = auth.uid();
$$;

-- ── 2. Fjern alle eksisterende profiles-policies (inkl. recursive) ─────────
DO $$
DECLARE
  pol record;
BEGIN
  FOR pol IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'profiles'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.profiles', pol.policyname);
  END LOOP;
END $$;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- ── 3. Nye policies — aldri subquery mot profiles ────────────────────────────

-- Les egen rad (login / onboarding)
CREATE POLICY profiles_select_own
ON public.profiles
FOR SELECT
TO authenticated
USING (id = auth.uid());

-- Superadmin ser alle profiler
CREATE POLICY profiles_select_superadmin
ON public.profiles
FOR SELECT
TO authenticated
USING (get_user_role() = 'superadmin'::public.user_role);

-- Admin/leder ser profiler i samme selskap
CREATE POLICY profiles_select_company
ON public.profiles
FOR SELECT
TO authenticated
USING (
  get_user_role() IN ('admin'::public.user_role, 'leder'::public.user_role)
  AND company_id IS NOT NULL
  AND company_id = get_user_company_id()
);

-- Oppdater egen profil
CREATE POLICY profiles_update_own
ON public.profiles
FOR UPDATE
TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- Admin/superadmin administrerer profiler i selskapet
CREATE POLICY profiles_update_admin
ON public.profiles
FOR UPDATE
TO authenticated
USING (
  get_user_role() IN ('admin'::public.user_role, 'superadmin'::public.user_role)
  AND company_id = get_user_company_id()
)
WITH CHECK (
  get_user_role() IN ('admin'::public.user_role, 'superadmin'::public.user_role)
  AND company_id = get_user_company_id()
);

CREATE POLICY profiles_insert_admin
ON public.profiles
FOR INSERT
TO authenticated
WITH CHECK (
  get_user_role() IN ('admin'::public.user_role, 'superadmin'::public.user_role)
  OR id = auth.uid()
);

CREATE POLICY profiles_delete_superadmin
ON public.profiles
FOR DELETE
TO authenticated
USING (get_user_role() = 'superadmin'::public.user_role);
