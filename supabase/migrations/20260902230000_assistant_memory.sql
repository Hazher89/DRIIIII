-- Kontinuerlig læring for DriftPro-assistenten (Q&A / driftsfakta).
CREATE TABLE IF NOT EXISTS public.assistant_memory (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  kind text NOT NULL DEFAULT 'fact',
  subject_key text,
  subject_user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  content text NOT NULL,
  visibility text NOT NULL DEFAULT 'company',
  source_query text,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_assistant_memory_company_created
  ON public.assistant_memory (company_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_assistant_memory_subject
  ON public.assistant_memory (company_id, subject_key, created_at DESC);

ALTER TABLE public.assistant_memory ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS assistant_memory_select ON public.assistant_memory;
CREATE POLICY assistant_memory_select ON public.assistant_memory
  FOR SELECT TO authenticated
  USING (company_id = public.get_user_company_id());

DROP POLICY IF EXISTS assistant_memory_insert ON public.assistant_memory;
CREATE POLICY assistant_memory_insert ON public.assistant_memory
  FOR INSERT TO authenticated
  WITH CHECK (
    company_id = public.get_user_company_id()
    AND created_by = auth.uid()
  );

COMMENT ON TABLE public.assistant_memory IS
  'Assistentens lærte fakta/hendelser. Appen filtrerer ytterligere etter GDPR (avdeling/principals).';
