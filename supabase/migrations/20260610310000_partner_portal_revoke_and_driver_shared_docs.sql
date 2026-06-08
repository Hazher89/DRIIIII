-- Opphev portal-tilgang ved fjernet MAVI/bil + sjåfør ser kun felles dokumentmapper.

CREATE OR REPLACE FUNCTION public.clear_stale_partner_portal_profile(p_uid UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_uid IS NULL THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.partner_portal_accounts ppa
    WHERE ppa.is_active = true
      AND (ppa.profile_id = p_uid OR lower(trim(ppa.login_email)) = (
        SELECT lower(trim(email)) FROM public.profiles WHERE id = p_uid
      ))
  ) THEN
    RETURN;
  END IF;

  UPDATE public.profiles
  SET
    partner_id = NULL,
    partner_vehicle_id = NULL
  WHERE id = p_uid
    AND role = 'samarbeidspartner'::public.user_role
    AND (partner_id IS NOT NULL OR partner_vehicle_id IS NOT NULL);
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_partner_bootstrap_to_profile()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  em TEXT := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  p UUID;
  c UUID;
  vid UUID;
BEGIN
  IF uid IS NULL THEN
    RETURN;
  END IF;

  SELECT ppa.partner_id, ppa.company_id, ppa.partner_vehicle_id
  INTO p, c, vid
  FROM public.partner_portal_accounts ppa
  WHERE ppa.is_active = true
    AND (
      ppa.profile_id = uid
      OR (em <> '' AND lower(trim(ppa.login_email)) = em)
    )
  ORDER BY CASE WHEN ppa.profile_id = uid THEN 0 ELSE 1 END
  LIMIT 1;

  IF p IS NULL THEN
    PERFORM public.clear_stale_partner_portal_profile(uid);
    RETURN;
  END IF;

  UPDATE public.profiles
  SET
    partner_id = p,
    company_id = coalesce(company_id, c),
    partner_vehicle_id = vid,
    role = 'samarbeidspartner'::public.user_role,
    is_onboarded = true,
    is_approved = true,
    is_active = true
  WHERE id = uid;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_shared_partner_document_folder(p_folder_id UUID)
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
      WHERE f.id = p_folder_id
        AND f.visibility = 'shared'
        AND coalesce(f.owner_managed, false) = false
    )
  END;
$$;

CREATE OR REPLACE FUNCTION public.can_access_partner_document_folder(p_folder_id UUID)
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
      WHERE f.id = p_folder_id
        AND (
          (
            public.is_partner_owner_profile()
            AND f.partner_id = public.profile_partner_id()
            AND (f.owner_managed = true OR f.visibility = 'shared')
          )
          OR (
            EXISTS (
              SELECT 1 FROM public.profiles p
              WHERE p.id = auth.uid()
                AND p.partner_vehicle_id IS NOT NULL
                AND p.partner_id = f.partner_id
            )
            AND f.visibility = 'shared'
            AND coalesce(f.owner_managed, false) = false
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
      EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = auth.uid()
          AND p.partner_vehicle_id IS NOT NULL
          AND p.partner_id = partner_document_folders.partner_id
      )
      AND visibility = 'shared'
      AND coalesce(owner_managed, false) = false
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
        AND public.is_shared_partner_document_folder(folder_id)
      )
    )
  )
);

-- Eksisterende dokumenter i felles mapper: synlig for sjåfør.
UPDATE public.partner_documents pd
SET driver_visible = true
FROM public.partner_document_folders f
WHERE pd.folder_id = f.id
  AND f.visibility = 'shared'
  AND coalesce(f.owner_managed, false) = false
  AND coalesce(pd.doc_category, 'general') IS DISTINCT FROM 'summary'
  AND coalesce(pd.driver_visible, false) = false;

GRANT EXECUTE ON FUNCTION public.clear_stale_partner_portal_profile(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_shared_partner_document_folder(UUID) TO authenticated;
