-- Rydd opp SAP staged-kø: korrekt kilde-tagg og kobling mot inbox.

UPDATE public.partner_route_shares prs
SET staged_import_source = 'sap'
FROM public.sap_route_inbox sri
WHERE sri.imported_route_share_id = prs.id
  AND prs.dispatch_status = 'staged'
  AND coalesce(prs.staged_import_source, 'manual') <> 'sap';

-- Pending inbox som allerede har staged-match — marker importert (unngår «nye» som egentlig er i kø).
UPDATE public.sap_route_inbox sri
SET
  status = 'imported',
  imported_route_share_id = prs.id,
  processed_at = coalesce(sri.processed_at, NOW())
FROM public.partner_route_shares prs
WHERE sri.status = 'pending'
  AND prs.dispatch_status = 'staged'
  AND prs.company_id = sri.company_id
  AND (
    lower(prs.title) LIKE '%' || lower(sri.file_name) || '%'
    OR lower(prs.pdf_storage_path) LIKE '%' || lower(replace(sri.file_name, '.pdf', '')) || '%'
    OR sri.content_sha256 IS NOT NULL
      AND prs.pdf_search_text IS NOT NULL
      AND length(prs.pdf_search_text) >= 120
  );
