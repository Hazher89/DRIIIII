-- GM & STORO — skannelapp-registrering (Glasmagasinet + Storo)

CREATE TABLE IF NOT EXISTS public.gm_storo_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'submitted')),
  label_count int NOT NULL DEFAULT 0,
  submitted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.gm_storo_scans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  batch_id uuid NOT NULL REFERENCES public.gm_storo_batches(id) ON DELETE CASCADE,
  scanned_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  sscc text NOT NULL,
  barcode_raw text,
  package_id text,
  shipment_id text,
  consignee text,
  recipient_name text,
  recipient_address text,
  recipient_postal text,
  weight_kg text,
  ready_time text,
  ready_date text,
  article_eg text,
  article_ndc text,
  area_code text,
  unit_type text,
  sender_name text,
  destination text CHECK (destination IS NULL OR destination IN ('gm', 'storo', 'other')),
  raw_ocr_text text,
  is_duplicate boolean NOT NULL DEFAULT false,
  scanned_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_gm_storo_batches_company
  ON public.gm_storo_batches (company_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_gm_storo_scans_batch
  ON public.gm_storo_scans (batch_id, scanned_at DESC);

CREATE INDEX IF NOT EXISTS idx_gm_storo_scans_company_sscc
  ON public.gm_storo_scans (company_id, sscc);

CREATE UNIQUE INDEX IF NOT EXISTS uq_gm_storo_scans_batch_sscc
  ON public.gm_storo_scans (batch_id, sscc);

ALTER TABLE public.gm_storo_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gm_storo_scans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS gm_storo_batches_select ON public.gm_storo_batches;
CREATE POLICY gm_storo_batches_select ON public.gm_storo_batches
  FOR SELECT USING (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS gm_storo_batches_insert ON public.gm_storo_batches;
CREATE POLICY gm_storo_batches_insert ON public.gm_storo_batches
  FOR INSERT WITH CHECK (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND created_by = auth.uid()
  );

DROP POLICY IF EXISTS gm_storo_batches_update ON public.gm_storo_batches;
CREATE POLICY gm_storo_batches_update ON public.gm_storo_batches
  FOR UPDATE USING (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND (
      created_by = auth.uid()
      OR (SELECT role::text FROM public.profiles WHERE id = auth.uid()) IN ('admin', 'superadmin', 'leder')
    )
  );

DROP POLICY IF EXISTS gm_storo_scans_select ON public.gm_storo_scans;
CREATE POLICY gm_storo_scans_select ON public.gm_storo_scans
  FOR SELECT USING (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS gm_storo_scans_insert ON public.gm_storo_scans;
CREATE POLICY gm_storo_scans_insert ON public.gm_storo_scans
  FOR INSERT WITH CHECK (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND scanned_by = auth.uid()
    AND batch_id IN (
      SELECT id FROM public.gm_storo_batches b
      WHERE b.company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
        AND b.status = 'draft'
        AND b.created_by = auth.uid()
    )
  );

DROP POLICY IF EXISTS gm_storo_scans_delete ON public.gm_storo_scans;
CREATE POLICY gm_storo_scans_delete ON public.gm_storo_scans
  FOR DELETE USING (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND (
      scanned_by = auth.uid()
      OR (SELECT role::text FROM public.profiles WHERE id = auth.uid()) IN ('admin', 'superadmin', 'leder')
    )
  );
