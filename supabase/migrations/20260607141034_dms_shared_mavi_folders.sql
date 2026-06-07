-- Felles DMS-mapper: synlig for alle MAVI-ansatte, ikke samarbeidspartnere.

ALTER TABLE public.dms_folders
  ADD COLUMN IF NOT EXISTS is_shared_mavi BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.dms_folders.is_shared_mavi IS
  'Felles mappe — alle interne MAVI-ansatte har lesetilgang; portalbrukere ekskluderes.';

CREATE OR REPLACE FUNCTION public.is_mavi_employee_profile(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = COALESCE(p_user_id, auth.uid())
      AND p.partner_id IS NULL
      AND p.role IS DISTINCT FROM 'samarbeidspartner'
      AND p.is_active IS NOT FALSE
  );
$$;

CREATE OR REPLACE FUNCTION public.can_access_dms_folder(p_folder_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_folder public.dms_folders%ROWTYPE;
  v_uid UUID := auth.uid();
  v_role TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RETURN false;
  END IF;

  SELECT * INTO v_folder FROM public.dms_folders WHERE id = p_folder_id;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  SELECT role::text INTO v_role FROM public.profiles WHERE id = v_uid;

  IF v_role IN ('admin', 'superadmin') THEN
    RETURN true;
  END IF;

  IF NOT public.is_mavi_employee_profile(v_uid) THEN
    RETURN false;
  END IF;

  IF v_folder.is_shared_mavi THEN
    RETURN true;
  END IF;

  IF NOT COALESCE(v_folder.is_private, false) THEN
    RETURN true;
  END IF;

  IF v_folder.created_by = v_uid THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.dms_permissions dp
    WHERE dp.folder_id = p_folder_id
      AND dp.user_id = v_uid
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.can_access_dms_file(p_file_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_file public.dms_files%ROWTYPE;
BEGIN
  SELECT * INTO v_file FROM public.dms_files WHERE id = p_file_id;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_file.folder_id IS NULL THEN
    RETURN public.is_mavi_employee_profile()
      OR EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role::text IN ('admin', 'superadmin')
      );
  END IF;

  RETURN public.can_access_dms_folder(v_file.folder_id);
END;
$$;

-- Strammere RLS: kun MAVI-ansatte + admin ser DMS; mapper respekterer ACL.
DROP POLICY IF EXISTS "DMS Folders Selskap" ON public.dms_folders;
CREATE POLICY "DMS Folders MAVI" ON public.dms_folders
  FOR SELECT
  USING (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND public.can_access_dms_folder(id)
  );

CREATE POLICY "DMS Folders MAVI write" ON public.dms_folders
  FOR INSERT
  WITH CHECK (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND public.is_mavi_employee_profile()
  );

CREATE POLICY "DMS Folders MAVI update" ON public.dms_folders
  FOR UPDATE
  USING (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND public.is_mavi_employee_profile()
  );

CREATE POLICY "DMS Folders MAVI delete" ON public.dms_folders
  FOR DELETE
  USING (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND (
      (SELECT role::text FROM public.profiles WHERE id = auth.uid()) IN ('admin', 'superadmin')
      OR created_by = auth.uid()
    )
  );

DROP POLICY IF EXISTS "DMS Files Selskap" ON public.dms_files;
CREATE POLICY "DMS Files MAVI read" ON public.dms_files
  FOR SELECT
  USING (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND public.can_access_dms_file(id)
  );

CREATE POLICY "DMS Files MAVI write" ON public.dms_files
  FOR INSERT
  WITH CHECK (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND public.is_mavi_employee_profile()
  );

CREATE POLICY "DMS Files MAVI update" ON public.dms_files
  FOR UPDATE
  USING (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND public.is_mavi_employee_profile()
  );

CREATE POLICY "DMS Files MAVI delete" ON public.dms_files
  FOR DELETE
  USING (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND public.is_mavi_employee_profile()
  );
