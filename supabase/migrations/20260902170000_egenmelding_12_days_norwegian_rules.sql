-- Egenmelding: 4 tilfeller × maks 3 dager = 12 dager totalt (ikke 24).
-- Retter feil standard fra tidligere schema.

ALTER TABLE public.companies
  ALTER COLUMN egenmelding_days_per_year SET DEFAULT 12,
  ALTER COLUMN egenmelding_consecutive_max SET DEFAULT 3;

UPDATE public.companies
SET egenmelding_days_per_year = 12
WHERE egenmelding_days_per_year IS NULL
   OR egenmelding_days_per_year > 12;

UPDATE public.companies
SET egenmelding_consecutive_max = 3
WHERE egenmelding_consecutive_max IS NULL
   OR egenmelding_consecutive_max > 3;

COMMENT ON COLUMN public.companies.egenmelding_days_per_year IS
  'Maks egenmeldingsdager i 12-mnd periode (typisk 12 = 4 tilfeller × 3 dager).';
COMMENT ON COLUMN public.companies.egenmelding_consecutive_max IS
  'Maks kalenderdager per egenmeldingsperiode (typisk 3).';
