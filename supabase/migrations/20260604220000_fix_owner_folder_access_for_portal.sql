-- Bedriftsansvarlig skal også se delte mapper og dokumenter i dem.

CREATE OR REPLACE FUNCTION public.can_access_partner_document_folder(p_folder_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_folder_id IS NULL THEN true
    ELSE EXISTS (
      SELECT 1 FROM public.partner_document_folders f
      WHERE f.id = p_folder_id
        AND (
          (
            public.is_partner_owner_profile()
            AND f.partner_id = public.profile_partner_id()
            AND (f.owner_managed = true OR f.visibility = 'shared')
          )
          OR (
            f.company_id IN (
              SELECT p.company_id FROM public.profiles p
              WHERE p.id = auth.uid() AND p.company_id IS NOT NULL
            )
            AND NOT EXISTS (
              SELECT 1 FROM public.profiles x
              WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
            )
            AND (
              f.visibility = 'shared'
              OR (f.visibility = 'private' AND NOT f.owner_managed)
              OR public.is_mavi_superadmin()
              OR EXISTS (
                SELECT 1 FROM public.partner_document_folder_access a
                WHERE a.folder_id = f.id AND a.profile_id = auth.uid()
              )
            )
          )
        )
    )
  END;
$$;

DROP POLICY IF EXISTS partner_document_folders_select ON public.partner_document_folders;
CREATE POLICY partner_document_folders_select ON public.partner_document_folders
  FOR SELECT USING (
    (
      public.is_partner_owner_profile()
      AND partner_id = public.profile_partner_id()
      AND (owner_managed = true OR visibility = 'shared')
    )
    OR (
      company_id IN (
        SELECT p.company_id FROM public.profiles p
        WHERE p.id = auth.uid() AND p.company_id IS NOT NULL
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.profiles x
        WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
      )
      AND (
        visibility = 'shared'
        OR NOT owner_managed
        OR public.is_mavi_superadmin()
        OR EXISTS (
          SELECT 1 FROM public.partner_document_folder_access a
          WHERE a.folder_id = partner_document_folders.id
            AND a.profile_id = auth.uid()
        )
      )
    )
  );
