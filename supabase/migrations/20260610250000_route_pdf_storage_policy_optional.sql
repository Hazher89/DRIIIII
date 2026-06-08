-- Valgfri storage-policy — kjør KUN via supabase db push / migrasjon som postgres,
-- IKKE vanlig SQL Editor (feiler med 42501 must be owner of relation objects).
-- Hopp over denne filen hvis du deployer manuelt i Dashboard.

DO $policy$
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE NOTICE 'Hopper over route_pdf_read-policy (krever postgres-eier). Eksisterende Document Access-policy er nok.';
    RETURN;
  END IF;

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
EXCEPTION
  WHEN insufficient_privilege OR SQLSTATE '42501' THEN
    RAISE NOTICE 'route_pdf_read-policy hoppet over — bruk Dashboard eller supabase db push.';
END $policy$;
