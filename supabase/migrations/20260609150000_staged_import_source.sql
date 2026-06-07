-- Skill AUTO MASS (manuell) fra Ruter fra SAP i staged-køen.

ALTER TABLE public.partner_route_shares
  ADD COLUMN IF NOT EXISTS staged_import_source TEXT
  CHECK (staged_import_source IS NULL OR staged_import_source IN ('manual', 'sap'));

COMMENT ON COLUMN public.partner_route_shares.staged_import_source IS
  'manual = AUTO MASS; sap = importert fra sap_route_inbox. Kun for dispatch_status = staged.';

-- Fjern feilaktige SAP-koblinger der kladden ligger i partner_routes/ men inbox har annen sti.
UPDATE public.sap_route_inbox sri
SET
  imported_route_share_id = NULL,
  status = 'pending',
  processed_at = NULL,
  processed_by = NULL
FROM public.partner_route_shares prs
WHERE sri.imported_route_share_id = prs.id
  AND prs.dispatch_status = 'staged'
  AND sri.pdf_storage_path IS DISTINCT FROM prs.pdf_storage_path
  AND prs.pdf_storage_path LIKE '%partner_routes/%';

UPDATE public.partner_route_shares prs
SET staged_import_source = 'sap'
FROM public.sap_route_inbox sri
WHERE sri.imported_route_share_id = prs.id
  AND prs.dispatch_status = 'staged';

UPDATE public.partner_route_shares
SET staged_import_source = 'manual'
WHERE dispatch_status = 'staged'
  AND staged_import_source IS NULL;
