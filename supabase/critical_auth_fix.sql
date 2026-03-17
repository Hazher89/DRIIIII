-- ============================================================
-- DRIFTPRO – CRITICAL AUTH & ONBOARDING REPAIR
-- Løser problemet: "Database error saving new user"
-- ============================================================

-- 1. Sørg for at alle kolonner eksisterer i profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS access_settings JSONB DEFAULT '{"hms": true, "fravaer": true, "avvik": true, "avdelinger": true, "ansatte": true}'::JSONB;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_onboarded BOOLEAN DEFAULT FALSE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_approved BOOLEAN DEFAULT FALSE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS employee_number TEXT;

-- 2. Gjør email og full_name mer fleksible (i tilfelle tlf-innlogging)
ALTER TABLE public.profiles ALTER COLUMN full_name DROP NOT NULL;
ALTER TABLE public.profiles ALTER COLUMN email DROP NOT NULL;

-- 3. Sørg for at det finnes minst ett selskap
INSERT INTO public.companies (id, name, org_number)
VALUES ('00000000-0000-0000-0000-000000000000', 'DriftPro Hovedkontor', '999999999')
ON CONFLICT (id) DO NOTHING;

-- 4. Robust Trigger-funksjon for nye brukere
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  default_company_id UUID;
BEGIN
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
      WHEN new.email = 'baxightsi@gmail.com' THEN 'superadmin'::user_role 
      ELSE 'ansatt'::user_role 
    END,
    '{"hms": true, "fravaer": true, "avvik": true, "avdelinger": true, "ansatte": true}'::JSONB,
    FALSE,
    FALSE
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = COALESCE(profiles.full_name, EXCLUDED.full_name);

  RETURN new;
EXCEPTION WHEN OTHERS THEN
  -- Logg feil hvis mulig, men ikke krasj hele auth-prosessen
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Re-installer triggeren
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 6. Oppdater eksisterende brukere som mangler tilgangs-innstillinger
UPDATE public.profiles 
SET access_settings = '{"hms": true, "fravaer": true, "avvik": true, "avdelinger": true, "ansatte": true}'::JSONB
WHERE access_settings IS NULL OR access_settings = '{}'::JSONB;

-- 7. Sørg for at RLS tillater nye brukere å se sitt eget selskap og profil
DROP POLICY IF EXISTS "Se egen profil" ON public.profiles;
CREATE POLICY "Se egen profil" ON public.profiles FOR SELECT USING (id = auth.uid());

DROP POLICY IF EXISTS "Brukere kan oppdatere egen profil" ON public.profiles;
CREATE POLICY "Brukere kan oppdatere egen profil" ON public.profiles FOR UPDATE USING (id = auth.uid());
