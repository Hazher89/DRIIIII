-- ============================================================
-- DRIFTPRO – FINAL SECURITY LOCKDOWN
-- Use this to ensure absolutely NO ONE bypasses approval.
-- ============================================================

-- 1. Reset defaults for existing columns to be SECURE
ALTER TABLE public.profiles ALTER COLUMN is_onboarded SET DEFAULT FALSE;
ALTER TABLE public.profiles ALTER COLUMN is_approved SET DEFAULT FALSE;
ALTER TABLE public.profiles ALTER COLUMN access_settings SET DEFAULT '{}'::JSONB;

-- 2. FORCE reset anyone who is currently in a "limbo" state (optional, but recommended)
-- This will kick out any unapproved users who might have been marked as approved by accident.
-- UPDATE public.profiles 
-- SET is_approved = FALSE 
-- WHERE role != 'superadmin' AND email != 'baxightsi@gmail.com';

-- 3. The ULTIMATE Trigger function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  default_company_id UUID;
  is_dev_account BOOLEAN;
BEGIN
  -- Sjekk om dette er hoved-utviklerkontoen
  is_dev_account := (new.email = 'baxightsi@gmail.com' OR new.email = 'baxigshti@hotmail.de');

  -- Hent første tilgjengelige selskap
  SELECT id INTO default_company_id FROM public.companies LIMIT 1;

  INSERT INTO public.profiles (
    id, 
    email, 
    full_name, 
    company_id, 
    role, 
    access_settings,
    is_onboarded,
    is_approved
  )
  VALUES (
    new.id, 
    new.email, 
    COALESCE(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', 'Ny Bruker'),
    default_company_id,
    CASE 
      WHEN is_dev_account THEN 'superadmin'::user_role 
      ELSE 'ansatt'::user_role 
    END,
    '{}'::JSONB, -- Start med INGEN tilgang
    FALSE,       -- Må onboardes
    CASE WHEN is_dev_account THEN TRUE ELSE FALSE END -- Kun dev er auto-godkjent
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    -- IKKE oppdater is_approved eller is_onboarded her, det ville vært et sikkerhetshull hvis auth-triggeren kan trigges manuelt
    full_name = COALESCE(profiles.full_name, EXCLUDED.full_name);

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Ensure RLS is strictly enforced
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Se egen profil" ON public.profiles;
CREATE POLICY "Se egen profil" ON public.profiles FOR SELECT USING (id = auth.uid());

-- Superadmin kan se ALT
DROP POLICY IF EXISTS "Superadmin ser alt" ON public.profiles;
CREATE POLICY "Superadmin ser alt" ON public.profiles 
FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND role = 'superadmin'
  )
);

-- 5. Helper to automatically sync Google metadata to profile if needed
-- (Sometimes Google login metadata is available later)
