-- DMS opplasting: definitiv fiks — trigger for company_id, enkel INSERT RLS, oppretter-SELECT.

-- 1) Synk company_id fra mappe FØR RLS WITH CHECK (fikser gamle klienter med feil company_id)
CREATE OR REPLACE FUNCTION public.dms_files_set_company_from_folder()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.folder_id IS NOT NULL THEN
    SELECT f.company_id INTO NEW.company_id
    FROM public.dms_folders f
    WHERE f.id = NEW.folder_id;
  ELSIF NEW.company_id IS NULL THEN
    NEW.company_id := COALESCE(
      public.get_user_company_id(),
      public.get_bootstrap_company_id()
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_dms_files_company ON public.dms_files;
CREATE TRIGGER trg_dms_files_company
  BEFORE INSERT ON public.dms_files
  FOR EACH ROW
  EXECUTE FUNCTION public.dms_files_set_company_from_folder();

-- 2) Opplaster ser alltid egen fil (INSERT … RETURNING og listevisning)
CREATE OR REPLACE FUNCTION public.can_access_dms_file(p_file_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_file public.dms_files%ROWTYPE;
  v_company UUID;
BEGIN
  SELECT * INTO v_file FROM public.dms_files WHERE id = p_file_id;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_file.created_by = auth.uid() THEN
    RETURN true;
  END IF;

  v_company := COALESCE(public.get_user_company_id(), public.get_bootstrap_company_id());

  IF v_company IS NOT NULL AND v_file.company_id IS DISTINCT FROM v_company THEN
    RETURN false;
  END IF;

  IF v_file.folder_id IS NULL THEN
    RETURN public.is_mavi_employee_profile()
      OR EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role::text IN ('admin', 'superadmin', 'leder')
      );
  END IF;

  RETURN public.can_access_dms_folder(v_file.folder_id);
END;
$$;

-- 3) Fjern alle eksisterende dms_files-policies (inkl. legacy «write»/«read»)
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'dms_files'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.dms_files', r.policyname);
  END LOOP;
END $$;

CREATE POLICY "DMS Files select" ON public.dms_files
  FOR SELECT TO authenticated
  USING (
    created_by = auth.uid()
    OR public.can_access_dms_file(id)
  );

CREATE POLICY "DMS Files insert" ON public.dms_files
  FOR INSERT TO authenticated
  WITH CHECK (
    created_by = auth.uid()
    AND public.is_mavi_employee_profile(auth.uid())
  );

CREATE POLICY "DMS Files update" ON public.dms_files
  FOR UPDATE TO authenticated
  USING (
    company_id IS NOT DISTINCT FROM COALESCE(
      public.get_user_company_id(),
      public.get_bootstrap_company_id()
    )
    AND public.is_mavi_employee_profile(auth.uid())
  )
  WITH CHECK (
    company_id IS NOT DISTINCT FROM COALESCE(
      public.get_user_company_id(),
      public.get_bootstrap_company_id()
    )
    AND public.is_mavi_employee_profile(auth.uid())
  );

CREATE POLICY "DMS Files delete" ON public.dms_files
  FOR DELETE TO authenticated
  USING (
    company_id IS NOT DISTINCT FROM COALESCE(
      public.get_user_company_id(),
      public.get_bootstrap_company_id()
    )
    AND public.is_mavi_employee_profile(auth.uid())
  );

-- 4) RPC: slå av row_security inne i funksjonen (belt + suspenders)
CREATE OR REPLACE FUNCTION public.insert_dms_file(
  p_folder_id UUID,
  p_name TEXT,
  p_storage_path TEXT,
  p_file_size BIGINT,
  p_extension TEXT,
  p_storage_provider TEXT DEFAULT 'supabase',
  p_external_url TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_profile public.profiles%ROWTYPE;
  v_folder public.dms_folders%ROWTYPE;
  v_row public.dms_files%ROWTYPE;
  v_company UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = v_uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profil mangler — logg ut og inn på nytt';
  END IF;

  IF v_profile.partner_id IS NOT NULL
     OR COALESCE(v_profile.role::text, '') = 'samarbeidspartner' THEN
    RAISE EXCEPTION 'Samarbeidspartnere har ikke tilgang til dokumentarkiv';
  END IF;

  IF COALESCE(v_profile.is_active, true) = false THEN
    RAISE EXCEPTION 'Kontoen er deaktivert';
  END IF;

  PERFORM set_config('row_security', 'off', true);

  IF p_folder_id IS NULL THEN
    v_company := COALESCE(v_profile.company_id, public.get_bootstrap_company_id());
    IF v_company IS NULL THEN
      RAISE EXCEPTION 'Profilen mangler bedriftstilknytning';
    END IF;

    IF COALESCE(v_profile.role::text, '') NOT IN ('admin', 'superadmin', 'leder')
       AND NOT public.is_mavi_employee_profile(v_uid) THEN
      RAISE EXCEPTION 'Ingen tilgang til opplasting';
    END IF;

    INSERT INTO public.dms_files (
      company_id, folder_id, name, storage_path, file_size, file_size_bytes,
      extension, created_by, storage_provider, external_url
    ) VALUES (
      v_company, NULL, p_name, p_storage_path, p_file_size, p_file_size,
      p_extension, v_uid, COALESCE(NULLIF(trim(p_storage_provider), ''), 'supabase'),
      NULLIF(trim(p_external_url), '')
    )
    RETURNING * INTO v_row;

    RETURN to_jsonb(v_row);
  END IF;

  SELECT * INTO v_folder FROM public.dms_folders WHERE id = p_folder_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mappe finnes ikke';
  END IF;

  IF COALESCE(v_profile.role::text, '') IN ('admin', 'superadmin', 'leder') THEN
    NULL;
  ELSIF COALESCE(v_folder.is_shared_mavi, false) THEN
    IF NOT public.is_mavi_employee_profile(v_uid) THEN
      RAISE EXCEPTION 'Kun interne MAVI-ansatte kan laste opp i felles mapper';
    END IF;
  ELSIF NOT COALESCE(v_folder.is_private, false) THEN
    IF NOT public.is_mavi_employee_profile(v_uid) THEN
      RAISE EXCEPTION 'Ingen tilgang til opplasting';
    END IF;
  ELSIF v_folder.created_by = v_uid THEN
    NULL;
  ELSIF EXISTS (
    SELECT 1 FROM public.dms_permissions dp
    WHERE dp.folder_id = p_folder_id AND dp.user_id = v_uid
  ) THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'Ingen skrivetilgang til mappen';
  END IF;

  INSERT INTO public.dms_files (
    company_id, folder_id, name, storage_path, file_size, file_size_bytes,
    extension, created_by, storage_provider, external_url
  ) VALUES (
    v_folder.company_id, p_folder_id, p_name, p_storage_path, p_file_size, p_file_size,
    p_extension, v_uid, COALESCE(NULLIF(trim(p_storage_provider), ''), 'supabase'),
    NULLIF(trim(p_external_url), '')
  )
  RETURNING * INTO v_row;

  RETURN to_jsonb(v_row);
END;
$$;

REVOKE ALL ON FUNCTION public.insert_dms_file(UUID, TEXT, TEXT, BIGINT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.insert_dms_file(UUID, TEXT, TEXT, BIGINT, TEXT, TEXT, TEXT) TO authenticated;
