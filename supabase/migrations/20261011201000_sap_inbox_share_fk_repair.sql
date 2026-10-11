-- SAP-innboks pekte på rute-id som ikke fantes, så «Hent» la alle PDF i manuell
-- med fremmednøkkelfeil. Koble på nytt mot partner_route_shares og slipp de radene
-- tilbake i køen.

UPDATE public.sap_route_inbox sri
SET imported_route_share_id = NULL
WHERE sri.imported_route_share_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.partner_route_shares prs
    WHERE prs.id = sri.imported_route_share_id
  );

ALTER TABLE public.sap_route_inbox
  DROP CONSTRAINT IF EXISTS sap_route_inbox_imported_route_share_id_fkey;

ALTER TABLE public.sap_route_inbox
  ADD CONSTRAINT sap_route_inbox_imported_route_share_id_fkey
  FOREIGN KEY (imported_route_share_id)
  REFERENCES public.partner_route_shares (id)
  ON DELETE SET NULL;

UPDATE public.sap_route_inbox
SET
  status = 'pending',
  imported_route_share_id = NULL,
  reject_reason = NULL,
  processed_at = NULL,
  processed_by = NULL
WHERE reject_reason ILIKE '%23503%'
   OR reject_reason ILIKE '%imported_route_share_id_fkey%'
   OR reject_reason ILIKE '%PostgrestException%imported_route_share%';
