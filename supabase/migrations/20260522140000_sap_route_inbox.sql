-- Innboks for rute-PDF fra SAP (Resend Inbound → ruter@driftpro.no)

CREATE TABLE IF NOT EXISTS public.sap_route_inbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'imported', 'rejected', 'duplicate')),
  sender_email TEXT,
  sender_name TEXT,
  subject TEXT,
  file_name TEXT NOT NULL,
  pdf_storage_path TEXT NOT NULL,
  resend_email_id TEXT NOT NULL,
  attachment_id TEXT,
  content_sha256 TEXT,
  detected_mavi_code TEXT,
  reject_reason TEXT,
  imported_route_share_id UUID REFERENCES public.partner_route_shares(id) ON DELETE SET NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at TIMESTAMPTZ,
  processed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_sap_route_inbox_resend_attachment
  ON public.sap_route_inbox (resend_email_id, COALESCE(attachment_id, file_name));

CREATE INDEX IF NOT EXISTS idx_sap_route_inbox_company_status
  ON public.sap_route_inbox (company_id, status, received_at DESC);

COMMENT ON TABLE public.sap_route_inbox IS 'SAP Backup Form PDF-er mottatt via Resend (ruter@driftpro.no)';

ALTER TABLE public.sap_route_inbox ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sap_route_inbox_select ON public.sap_route_inbox;
CREATE POLICY sap_route_inbox_select ON public.sap_route_inbox
  FOR SELECT USING (
    company_id IN (
      SELECT p.company_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.company_id IS NOT NULL
    )
  );

DROP POLICY IF EXISTS sap_route_inbox_update ON public.sap_route_inbox;
CREATE POLICY sap_route_inbox_update ON public.sap_route_inbox
  FOR UPDATE USING (
    company_id IN (
      SELECT p.company_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.company_id IS NOT NULL
    )
  );

DROP POLICY IF EXISTS sap_route_inbox_delete ON public.sap_route_inbox;
CREATE POLICY sap_route_inbox_delete ON public.sap_route_inbox
  FOR DELETE USING (
    company_id IN (
      SELECT p.company_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.company_id IS NOT NULL
    )
  );
