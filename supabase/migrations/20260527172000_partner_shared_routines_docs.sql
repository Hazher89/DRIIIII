-- Felles rutiner/prosedyrer for alle samarbeidspartnere i samme selskap.

CREATE TABLE IF NOT EXISTS public.partner_shared_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  storage_path TEXT NOT NULL,
  file_name TEXT,
  mime_type TEXT,
  category TEXT NOT NULL DEFAULT 'routine'
    CHECK (category IN ('routine', 'procedure', 'manual', 'hms')),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_partner_shared_documents_company
  ON public.partner_shared_documents(company_id, created_at DESC);

ALTER TABLE public.partner_shared_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS partner_shared_documents_select ON public.partner_shared_documents;
CREATE POLICY partner_shared_documents_select ON public.partner_shared_documents
  FOR SELECT USING (
    company_id IN (
      SELECT p.company_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.company_id IS NOT NULL
    )
  );

DROP POLICY IF EXISTS partner_shared_documents_insert ON public.partner_shared_documents;
CREATE POLICY partner_shared_documents_insert ON public.partner_shared_documents
  FOR INSERT WITH CHECK (
    company_id IN (
      SELECT p.company_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.company_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x
      WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  );

DROP POLICY IF EXISTS partner_shared_documents_update ON public.partner_shared_documents;
CREATE POLICY partner_shared_documents_update ON public.partner_shared_documents
  FOR UPDATE USING (
    company_id IN (
      SELECT p.company_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.company_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x
      WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  );

DROP POLICY IF EXISTS partner_shared_documents_delete ON public.partner_shared_documents;
CREATE POLICY partner_shared_documents_delete ON public.partner_shared_documents
  FOR DELETE USING (
    company_id IN (
      SELECT p.company_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.company_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x
      WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.partner_shared_documents TO authenticated;
