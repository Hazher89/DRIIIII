-- Normaliser pdf_storage_path: fjern ødelagte public Supabase-URL-er, behold relativ sti.

UPDATE public.partner_route_shares
SET pdf_storage_path = regexp_replace(
  pdf_storage_path,
  '^https?://[^/]+/storage/v1/object/(?:public|sign|authenticated)/documents/',
  ''
)
WHERE pdf_storage_path ~ '^https?://.*/storage/v1/object/.*/documents/';

UPDATE public.partner_route_shares
SET pdf_storage_path = regexp_replace(pdf_storage_path, '\?.*$', '')
WHERE pdf_storage_path LIKE '%?%';

UPDATE public.sap_route_inbox
SET pdf_storage_path = regexp_replace(
  pdf_storage_path,
  '^https?://[^/]+/storage/v1/object/(?:public|sign|authenticated)/documents/',
  ''
)
WHERE pdf_storage_path ~ '^https?://.*/storage/v1/object/.*/documents/';

COMMENT ON COLUMN public.partner_route_shares.pdf_storage_path IS
  'dropbox://… eller relativ sti company_<uuid>/partner_routes/… — ikke public URL.';
