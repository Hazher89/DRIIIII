-- Fix infinite RLS recursion on partner_document_folders ↔ partner_document_folder_access.
-- Also avoid direct folder reads from partner_documents policies.

CREATE OR REPLACE FUNCTION public.is_owner_managed_folder(p_folder_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_folder_id IS NULL THEN false
    ELSE EXISTS (
      SELECT 1 FROM public.partner_document_folders f
      WHERE f.id = p_folder_id AND f.owner_managed = true
    )
  END;
$$;

CREATE OR REPLACE FUNCTION public.is_folder_owner_for_access(p_folder_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_partner_owner_profile()
    AND EXISTS (
      SELECT 1 FROM public.partner_document_folders f
      WHERE f.id = p_folder_id
        AND f.owner_managed = true
        AND f.partner_id = public.profile_partner_id()
    );
$$;

CREATE OR REPLACE FUNCTION public.is_private_owner_managed_folder(
  p_folder_id UUID,
  p_partner_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.partner_document_folders f
    WHERE f.id = p_folder_id
      AND f.partner_id = p_partner_id
      AND f.owner_managed = true
      AND f.visibility = 'private'
  );
$$;

DROP POLICY IF EXISTS partner_document_folders_select ON public.partner_document_folders;
CREATE POLICY partner_document_folders_select ON public.partner_document_folders
  FOR SELECT USING (public.can_access_partner_document_folder(id));

DROP POLICY IF EXISTS partner_document_folder_access_select ON public.partner_document_folder_access;
CREATE POLICY partner_document_folder_access_select ON public.partner_document_folder_access
  FOR SELECT USING (
    public.is_mavi_superadmin()
    OR profile_id = auth.uid()
    OR public.is_folder_owner_for_access(folder_id)
  );

DROP POLICY IF EXISTS "partner_documents_select" ON public.partner_documents;
CREATE POLICY "partner_documents_select" ON public.partner_documents FOR SELECT USING (
  (
    coalesce(doc_category, 'general') = 'summary'
    AND (
      public.is_mavi_superadmin()
      OR (
        partner_id IN (
          SELECT p.partner_id FROM public.profiles p
          WHERE p.id = auth.uid()
            AND p.partner_id IS NOT NULL
            AND p.partner_vehicle_id IS NULL
        )
        AND coalesce(owner_visible, true) = true
      )
    )
  )
  OR (
    coalesce(doc_category, 'general') IS DISTINCT FROM 'summary'
    AND public.can_access_partner_document_folder(folder_id)
    AND (
      (
        company_id IN (
          SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
        )
      )
      OR (
        partner_id IN (
          SELECT p.partner_id FROM public.profiles p
          WHERE p.id = auth.uid() AND p.partner_id IS NOT NULL AND p.partner_vehicle_id IS NULL
        )
        AND coalesce(owner_visible, true) = true
      )
      OR (
        partner_id IN (
          SELECT p.partner_id FROM public.profiles p
          WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
        )
        AND coalesce(driver_visible, false) = true
        AND NOT public.is_owner_managed_folder(folder_id)
      )
    )
  )
);

DROP POLICY IF EXISTS "partner_documents_insert_owner" ON public.partner_documents;
CREATE POLICY "partner_documents_insert_owner" ON public.partner_documents FOR INSERT
WITH CHECK (
  coalesce(doc_category, 'general') IS DISTINCT FROM 'summary'
  AND public.is_partner_owner_profile()
  AND partner_id = public.profile_partner_id()
  AND coalesce(owner_visible, true) = true
  AND coalesce(driver_visible, false) = false
  AND public.is_private_owner_managed_folder(folder_id, partner_id)
);

DROP POLICY IF EXISTS "partner_documents_delete_owner" ON public.partner_documents;
CREATE POLICY "partner_documents_delete_owner" ON public.partner_documents FOR DELETE
USING (
  coalesce(doc_category, 'general') IS DISTINCT FROM 'summary'
  AND public.is_partner_owner_profile()
  AND partner_id = public.profile_partner_id()
  AND public.is_private_owner_managed_folder(folder_id, partner_id)
);

GRANT EXECUTE ON FUNCTION public.is_owner_managed_folder(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_folder_owner_for_access(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_private_owner_managed_folder(UUID, UUID) TO authenticated;
