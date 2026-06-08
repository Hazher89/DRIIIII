-- Sikre at documents-bucket finnes (unngår «Bucket not found» ved rute-PDF).
-- MERK: storage.objects-policy kan ikke opprettes fra SQL Editor (42501).
--       Eksisterende policy «Document Access» (dms_setup) gir allerede lesing
--       for innloggede brukere med profil. Opprett bucket manuelt i Dashboard
--       hvis INSERT under også feiler.

DO $$
BEGIN
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
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE
      'Kunne ikke opprette bucket via SQL. Gå til Supabase Dashboard → Storage → '
      'New bucket: id=documents, public=OFF.';
  WHEN OTHERS THEN
    RAISE NOTICE 'documents-bucket: %', SQLERRM;
END $$;
