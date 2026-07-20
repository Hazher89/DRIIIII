-- ECO Driving Kurs for samarbeidspartnere (bedriftsnivå).
ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS eco_driving_completed BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS eco_driving_deadline DATE,
  ADD COLUMN IF NOT EXISTS eco_driving_completed_at DATE;

COMMENT ON COLUMN public.partners.eco_driving_completed IS
  'True når bedriften har gjennomført ECO Driving Kurs.';
COMMENT ON COLUMN public.partners.eco_driving_deadline IS
  'Frist for å ta kurset (typisk 3 måneder fra registrering).';
COMMENT ON COLUMN public.partners.eco_driving_completed_at IS
  'Dato kurset ble registrert som gjennomført.';

CREATE INDEX IF NOT EXISTS idx_partners_eco_driving_completed
  ON public.partners (company_id, eco_driving_completed);
