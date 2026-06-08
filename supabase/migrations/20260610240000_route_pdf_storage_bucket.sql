-- Sikre at documents-bucket finnes (unngår «Bucket not found» ved rute-PDF).
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'documents',
  'documents',
  false,
  52428800,
  ARRAY['application/pdf', 'image/jpeg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = EXCLUDED.file_size_limit;

-- Partner-portal og MAVI-ansatte kan lese rute-PDF-er i documents.
DROP POLICY IF EXISTS "route_pdf_read" ON storage.objects;
CREATE POLICY "route_pdf_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documents'
    AND (
      name LIKE 'company_%/partner_routes/%'
      OR name LIKE 'company_%/routes/%'
    )
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.is_active = true
        AND p.is_approved = true
    )
  );

COMMENT ON POLICY "route_pdf_read" ON storage.objects IS
  'Rute-PDF: alle godkjente brukere (inkl. bedriftsansvarlig/sjåfør) kan lese partner_routes/.';
