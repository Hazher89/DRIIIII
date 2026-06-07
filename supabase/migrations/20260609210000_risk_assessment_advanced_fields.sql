-- Utvidet risikoanalyse: flere felt, dokumenter, behandlingsstatus.

ALTER TABLE public.risk_assessments
  ADD COLUMN IF NOT EXISTS document_urls jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS hazard_source text,
  ADD COLUMN IF NOT EXISTS affected_persons text,
  ADD COLUMN IF NOT EXISTS legal_reference text,
  ADD COLUMN IF NOT EXISTS evaluation_method text,
  ADD COLUMN IF NOT EXISTS root_cause text,
  ADD COLUMN IF NOT EXISTS treatment_notes text,
  ADD COLUMN IF NOT EXISTS review_notes text,
  ADD COLUMN IF NOT EXISTS residual_measures text,
  ADD COLUMN IF NOT EXISTS iso_standard text,
  ADD COLUMN IF NOT EXISTS activity_process text,
  ADD COLUMN IF NOT EXISTS location_detail text,
  ADD COLUMN IF NOT EXISTS deadline date,
  ADD COLUMN IF NOT EXISTS treated_at timestamptz,
  ADD COLUMN IF NOT EXISTS treated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.risk_assessments.document_urls IS
  'JSON-liste: [{url, file_name, mime_type, uploaded_at}]';
COMMENT ON COLUMN public.risk_assessments.status IS
  'utkast | aktiv | under_behandling | behandlet | arkivert';

CREATE INDEX IF NOT EXISTS idx_risk_assessments_status
  ON public.risk_assessments (company_id, status);
