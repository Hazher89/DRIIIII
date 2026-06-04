-- Unngå duplikat SAP-PDF (samme innhold) innen 48 timer — typisk Resend/webhook-retry.

CREATE INDEX IF NOT EXISTS idx_sap_route_inbox_company_hash_recent
  ON public.sap_route_inbox (company_id, content_sha256, received_at DESC)
  WHERE content_sha256 IS NOT NULL
    AND status IN ('pending', 'imported');

COMMENT ON INDEX idx_sap_route_inbox_company_hash_recent IS
  'Støtter dedup av identisk PDF-innhold fra SAP innen kort tidsvindu';
