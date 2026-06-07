-- DMS opplasting: SECURITY DEFINER RPC omgår RLS INSERT-problemer.

-- Felles-mapper uten flagg
UPDATE public.dms_folders
SET is_shared_mavi = true
WHERE NOT COALESCE(is_shared_mavi, false)
  AND upper(trim(name)) IN ('FELLES', 'OPPLÆRING', 'OPPLAERING');

-- Én bedrift: align interne profiler med DMS-data
DO $$
DECLARE
  v_cid UUID;
BEGIN
  SELECT f.company_id INTO v_cid
  FROM public.dms_folders f
  GROUP BY f.company_id
  ORDER BY count(*) DESC
  LIMIT 1;

  IF v_cid IS NOT NULL THEN
    UPDATE public.profiles p
    SET company_id = v_cid
    WHERE p.partner_id IS NULL
      AND COALESCE(p.role::text, 'ansatt') <> 'samarbeidspartner'
      AND p.company_id IS DISTINCT FROM v_cid;
  END IF;
END $$;

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

-- Diagnostikk (superadmin)
CREATE OR REPLACE FUNCTION public.debug_dms_upload_access(p_folder_id UUID DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_profile public.profiles%ROWTYPE;
  v_folder public.dms_folders%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = v_uid;

  IF p_folder_id IS NOT NULL THEN
    SELECT * INTO v_folder FROM public.dms_folders WHERE id = p_folder_id;
  END IF;

  RETURN jsonb_build_object(
    'uid', v_uid,
    'role', v_profile.role::text,
    'company_id', v_profile.company_id,
    'partner_id', v_profile.partner_id,
    'is_mavi', public.is_mavi_employee_profile(v_uid),
    'can_insert_fn', public.can_insert_dms_file(p_folder_id, COALESCE(v_folder.company_id, v_profile.company_id)),
    'can_access_folder', CASE WHEN p_folder_id IS NULL THEN NULL ELSE public.can_access_dms_folder(p_folder_id) END,
    'folder', CASE WHEN v_folder.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_folder.id,
      'name', v_folder.name,
      'company_id', v_folder.company_id,
      'is_shared_mavi', v_folder.is_shared_mavi,
      'is_private', v_folder.is_private
    ) END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.debug_dms_upload_access(UUID) TO authenticated;
