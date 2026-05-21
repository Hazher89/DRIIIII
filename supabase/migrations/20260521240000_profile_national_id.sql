-- Fødselsnummer (11 siffer) for bursdagsoversikt og personalia.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS national_id_number TEXT;

COMMENT ON COLUMN public.profiles.national_id_number IS
  'Norsk fødselsnummer (11 siffer, uten mellomrom). Brukes bl.a. til bursdagskalender.';

CREATE INDEX IF NOT EXISTS idx_profiles_national_id
  ON public.profiles (national_id_number)
  WHERE national_id_number IS NOT NULL;
