-- Bedriftsansvarlig (bil-eier): egne mapper med begrenset MAVI-tilgang.
-- Synlig for: superadmin, bil-eier, MAVI-ansatte med eksplisitt mappe-tilgang.

ALTER TABLE public.partner_document_folders
  ADD COLUMN IF NOT EXISTS owner_managed BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS public.partner_document_folder_access (
  folder_id UUID NOT NULL REFERENCES public.partner_document_folders(id) ON DELETE CASCADE,
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  granted_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (folder_id, profile_id)
);

CREATE INDEX IF NOT EXISTS idx_partner_document_folder_access_profile
  ON public.partner_document_folder_access(profile_id);

ALTER TABLE public.partner_document_folder_access ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_partner_owner_profile()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.partner_id IS NOT NULL
      AND p.partner_vehicle_id IS NULL
  );
$$;

CREATE OR REPLACE FUNCTION public.profile_partner_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.partner_id FROM public.profiles p WHERE p.id = auth.uid() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.is_mavi_superadmin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role::text = 'superadmin'
  );
$$;

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

-- Mapper: begrenset lesing for bedriftens egne mapper
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

DROP POLICY IF EXISTS partner_document_folder_access_select ON public.partner_document_folder_access;
CREATE POLICY partner_document_folder_access_select ON public.partner_document_folder_access
  FOR SELECT USING (
    public.is_mavi_superadmin()
    OR profile_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.partner_document_folders f
      WHERE f.id = folder_id
        AND f.owner_managed = true
        AND f.partner_id = public.profile_partner_id()
        AND public.is_partner_owner_profile()
    )
  );

DROP POLICY IF EXISTS partner_document_folder_access_write ON public.partner_document_folder_access;
CREATE POLICY partner_document_folder_access_write ON public.partner_document_folder_access
  FOR ALL USING (public.is_mavi_superadmin())
  WITH CHECK (public.is_mavi_superadmin());

GRANT SELECT ON public.partner_document_folder_access TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.partner_document_folder_access TO authenticated;

-- Dokumenter: respekter mappe-tilgang; sjåfør ser ikke bedriftens egne mapper
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
        AND NOT EXISTS (
          SELECT 1 FROM public.partner_document_folders f
          WHERE f.id = folder_id AND f.owner_managed = true
        )
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
  AND EXISTS (
    SELECT 1 FROM public.partner_document_folders f
    WHERE f.id = folder_id
      AND f.partner_id = partner_documents.partner_id
      AND f.owner_managed = true
      AND f.visibility = 'private'
  )
);

DROP POLICY IF EXISTS "partner_documents_delete_owner" ON public.partner_documents;
CREATE POLICY "partner_documents_delete_owner" ON public.partner_documents FOR DELETE
USING (
  coalesce(doc_category, 'general') IS DISTINCT FROM 'summary'
  AND public.is_partner_owner_profile()
  AND partner_id = public.profile_partner_id()
  AND EXISTS (
    SELECT 1 FROM public.partner_document_folders f
    WHERE f.id = folder_id
      AND f.partner_id = partner_documents.partner_id
      AND f.owner_managed = true
  )
);

CREATE OR REPLACE FUNCTION public.create_owner_partner_document_folder(
  p_partner_id UUID,
  p_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name TEXT;
  v_company_id UUID;
  v_folder_id UUID;
BEGIN
  IF NOT public.is_partner_owner_profile() THEN
    RAISE EXCEPTION 'Kun bedriftsansvarlig kan opprette egne mapper';
  END IF;
  IF public.profile_partner_id() IS DISTINCT FROM p_partner_id THEN
    RAISE EXCEPTION 'Ingen tilgang til denne bedriften';
  END IF;

  v_name := nullif(trim(p_name), '');
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Mappenavn mangler';
  END IF;

  SELECT company_id INTO v_company_id
  FROM public.partners
  WHERE id = p_partner_id;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Ugyldig partner';
  END IF;

  INSERT INTO public.partner_document_folders(
    company_id, partner_id, name, visibility, owner_managed, created_by
  )
  VALUES (v_company_id, p_partner_id, v_name, 'private', true, auth.uid())
  ON CONFLICT (partner_id, name) DO UPDATE
    SET owner_managed = true,
        visibility = 'private'
  RETURNING id INTO v_folder_id;

  RETURN v_folder_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_owner_partner_document_folder(p_folder_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_partner_id UUID;
  v_deleted INTEGER := 0;
  v_paths TEXT[];
BEGIN
  SELECT f.partner_id INTO v_partner_id
  FROM public.partner_document_folders f
  WHERE f.id = p_folder_id
    AND f.owner_managed = true
    AND f.visibility = 'private';

  IF v_partner_id IS NULL THEN
    RAISE EXCEPTION 'Mappe ikke funnet';
  END IF;

  IF NOT public.is_partner_owner_profile()
     OR public.profile_partner_id() IS DISTINCT FROM v_partner_id THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  SELECT coalesce(array_agg(pd.storage_path), ARRAY[]::TEXT[])
  INTO v_paths
  FROM public.partner_documents pd
  WHERE pd.folder_id = p_folder_id;

  DELETE FROM public.partner_documents WHERE folder_id = p_folder_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  DELETE FROM public.partner_document_folders WHERE id = p_folder_id;

  RETURN v_deleted;
END;
$$;

CREATE OR REPLACE FUNCTION public.grant_partner_document_folder_access(
  p_folder_id UUID,
  p_profile_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_folder RECORD;
BEGIN
  IF NOT public.is_mavi_superadmin() THEN
    RAISE EXCEPTION 'Kun superadmin kan gi mappe-tilgang';
  END IF;

  SELECT f.id, f.company_id, f.owner_managed
  INTO v_folder
  FROM public.partner_document_folders f
  WHERE f.id = p_folder_id;

  IF v_folder.id IS NULL OR NOT v_folder.owner_managed THEN
    RAISE EXCEPTION 'Ugyldig bedriftsmappe';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = p_profile_id
      AND p.company_id = v_folder.company_id
      AND p.partner_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Ugyldig MAVI-bruker';
  END IF;

  INSERT INTO public.partner_document_folder_access(folder_id, profile_id, granted_by)
  VALUES (p_folder_id, p_profile_id, auth.uid())
  ON CONFLICT (folder_id, profile_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_partner_document_folder_access(
  p_folder_id UUID,
  p_profile_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_mavi_superadmin() THEN
    RAISE EXCEPTION 'Kun superadmin kan fjerne mappe-tilgang';
  END IF;

  DELETE FROM public.partner_document_folder_access
  WHERE folder_id = p_folder_id AND profile_id = p_profile_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_partner_document_folder(
  p_company_id UUID,
  p_partner_id UUID,
  p_name TEXT,
  p_visibility TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name TEXT;
  v_template_id UUID;
  v_folder_id UUID;
  r_partner RECORD;
BEGIN
  v_name := nullif(trim(p_name), '');
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Mappenavn mangler';
  END IF;
  IF p_visibility NOT IN ('private', 'shared') THEN
    RAISE EXCEPTION 'Ugyldig mappevalg';
  END IF;

  IF p_visibility = 'private' THEN
    INSERT INTO public.partner_document_folders(
      company_id, partner_id, name, visibility, owner_managed, created_by
    )
    VALUES (p_company_id, p_partner_id, v_name, 'private', false, auth.uid())
    ON CONFLICT (partner_id, name) DO UPDATE
      SET visibility = 'private',
          owner_managed = false
    RETURNING id INTO v_folder_id;
    RETURN v_folder_id;
  END IF;

  INSERT INTO public.partner_document_folder_templates(
    company_id, name, created_by
  )
  VALUES (p_company_id, v_name, auth.uid())
  ON CONFLICT (company_id, name) DO UPDATE SET is_active = true
  RETURNING id INTO v_template_id;

  FOR r_partner IN
    SELECT id FROM public.partners
    WHERE company_id = p_company_id AND is_active = true
  LOOP
    INSERT INTO public.partner_document_folders(
      company_id, partner_id, name, visibility, template_id, owner_managed, created_by
    )
    VALUES (p_company_id, r_partner.id, v_name, 'shared', v_template_id, false, auth.uid())
    ON CONFLICT (partner_id, name) DO UPDATE
      SET template_id = EXCLUDED.template_id,
          visibility = 'shared',
          owner_managed = false;
  END LOOP;

  SELECT id INTO v_folder_id
  FROM public.partner_document_folders
  WHERE partner_id = p_partner_id AND name = v_name
  LIMIT 1;

  RETURN v_folder_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_owner_partner_document_folder(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_owner_partner_document_folder(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.grant_partner_document_folder_access(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_partner_document_folder_access(UUID, UUID) TO authenticated;

COMMENT ON COLUMN public.partner_document_folders.owner_managed IS
  'true = opprettet av bedriftsansvarlig; kun superadmin, eier og tildelte MAVI-brukere.';
