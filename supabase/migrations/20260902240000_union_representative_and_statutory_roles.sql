-- Tillitsvalgt (union / employee representative) + tydelig verneombud-flagg.
-- Tilganger styres i access_settings; flaggene markerer verv iht. norsk lov.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_union_representative boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.profiles.is_safety_representative IS
  'Verneombud (arbeidsmiljøloven kap. 6). Auto-tilgang til HMS/vernerunde m.m. via app.';

COMMENT ON COLUMN public.profiles.is_union_representative IS
  'Tillitsvalgt (AML § 8 info/drøfting m.m.). Auto-tilgang til relevante moduler via app.';

CREATE INDEX IF NOT EXISTS profiles_safety_rep_idx
  ON public.profiles (company_id)
  WHERE is_safety_representative = true AND is_active = true;

CREATE INDEX IF NOT EXISTS profiles_union_rep_idx
  ON public.profiles (company_id)
  WHERE is_union_representative = true AND is_active = true;
