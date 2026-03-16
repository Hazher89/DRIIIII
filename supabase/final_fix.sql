-- ============================================================
-- DRIFTPRO – MASTER REPAIR SCRIPT (KJØR DENNE!)
-- ============================================================

-- 1. Sørg for at selskap eksisterer
INSERT INTO public.companies (id, name, org_number)
VALUES ('00000000-0000-0000-0000-000000000000', 'DriftPro Demo Selskap', '999999999')
ON CONFLICT (id) DO NOTHING;

-- 2. Reparer funksjoner for å unngå RLS-rekursjon
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS text AS $$
  -- Bruk SECURITY DEFINER for å omgå RLS og unngå "recursive search"
  SELECT role::text FROM public.profiles WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.get_user_company_id()
RETURNS uuid AS $$
  SELECT company_id FROM public.profiles WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- 3. Åpne opp PROFILES slik at man alltid kan se sin egen profil (viktig for login)
ALTER TABLE public.profiles DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Se egen profil" ON public.profiles;
CREATE POLICY "Se egen profil" ON public.profiles FOR SELECT USING (id = auth.uid());

DROP POLICY IF EXISTS "Se selskapsprofiler" ON public.profiles;
CREATE POLICY "Se selskapsprofiler" ON public.profiles FOR SELECT 
USING (company_id = (SELECT p.company_id FROM public.profiles p WHERE p.id = auth.uid()));

DROP POLICY IF EXISTS "Admin full tilgang" ON public.profiles;
CREATE POLICY "Admin full tilgang" ON public.profiles FOR ALL 
USING (auth.jwt() ->> 'email' = 'baxightsi@gmail.com' OR (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('admin', 'superadmin'));

-- 4. Knytt baxightsi@gmail.com til selskapet og gi rolle
UPDATE public.profiles 
SET 
  company_id = (SELECT id FROM public.companies LIMIT 1),
  role = 'superadmin',
  access_settings = '{
    "hms": true,
    "fravaer": true,
    "avvik": true,
    "avdelinger": true,
    "ansatte": true
  }'::JSONB
WHERE email = 'baxightsi@gmail.com';

-- 5. Sørg for at alle andre har et selskap
UPDATE public.profiles SET company_id = (SELECT id FROM public.companies LIMIT 1) WHERE company_id IS NULL;

-- 6. HMS Tabeller - Enkel RLS som alltid virker for selskapet
ALTER TABLE public.sja_forms DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.sja_forms ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "SJA Selskap" ON public.sja_forms;
CREATE POLICY "SJA Selskap" ON public.sja_forms FOR ALL USING (company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid()));

ALTER TABLE public.risk_assessments DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.risk_assessments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Risiko Selskap" ON public.risk_assessments;
CREATE POLICY "Risiko Selskap" ON public.risk_assessments FOR ALL USING (company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid()));

ALTER TABLE public.safety_rounds DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.safety_rounds ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Vernerunde Selskap" ON public.safety_rounds;
CREATE POLICY "Vernerunde Selskap" ON public.safety_rounds FOR ALL USING (company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid()));

-- 7. Fiks triggeren for nye brukere
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, company_id, role, access_settings)
  VALUES (
    new.id, 
    new.email, 
    COALESCE(new.raw_user_meta_data->>'full_name', new.email),
    (SELECT id FROM public.companies LIMIT 1),
    CASE WHEN new.email = 'baxightsi@gmail.com' THEN 'superadmin'::user_role ELSE 'ansatt'::user_role END,
    '{"hms": true, "fravaer": true, "avvik": true, "avdelinger": true, "ansatte": true}'::JSONB
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Ferdig! Kjører du denne i SQL Editor, skal alt fungere.
