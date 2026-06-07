-- Reparer DMS RLS-policies etter delvis manuell kjøring (idempotent).

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
      AND COALESCE(p.role::text, 'ansatt') NOT IN ('samarbeidspartner')
      AND COALESCE(p.is_active, true) = true
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

  SELECT role::text INTO v_role FROM public.profiles WHERE id = v_uid;

  IF v_role IN ('admin', 'superadmin') THEN
    RETURN true;
  END IF;

  IF NOT public.is_mavi_employee_profile(v_uid) THEN
    RETURN false;
  END IF;

  SELECT * INTO v_folder FROM public.dms_folders WHERE id = p_folder_id;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF COALESCE(v_folder.is_shared_mavi, false) THEN
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

CREATE OR REPLACE FUNCTION public.can_insert_dms_folder(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    auth.uid() IS NOT NULL
    AND p_company_id IS NOT NULL
    AND p_company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND public.is_mavi_employee_profile(auth.uid());
$$;

-- Mapper
DROP POLICY IF EXISTS "DMS Folders Selskap" ON public.dms_folders;
DROP POLICY IF EXISTS "DMS Folders MAVI" ON public.dms_folders;
DROP POLICY IF EXISTS "DMS Folders MAVI write" ON public.dms_folders;
DROP POLICY IF EXISTS "DMS Folders MAVI update" ON public.dms_folders;
DROP POLICY IF EXISTS "DMS Folders MAVI delete" ON public.dms_folders;
DROP POLICY IF EXISTS "DMS Folders MAVI insert" ON public.dms_folders;
DROP POLICY IF EXISTS "DMS Folders MAVI select" ON public.dms_folders;

CREATE POLICY "DMS Folders MAVI select" ON public.dms_folders
  FOR SELECT
  USING (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND public.can_access_dms_folder(id)
  );

CREATE POLICY "DMS Folders MAVI insert" ON public.dms_folders
  FOR INSERT
  WITH CHECK (public.can_insert_dms_folder(company_id));

CREATE POLICY "DMS Folders MAVI update" ON public.dms_folders
  FOR UPDATE
  USING (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND public.is_mavi_employee_profile()
  )
  WITH CHECK (
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

-- Filer
DROP POLICY IF EXISTS "DMS Files Selskap" ON public.dms_files;
DROP POLICY IF EXISTS "DMS Files MAVI read" ON public.dms_files;
DROP POLICY IF EXISTS "DMS Files MAVI write" ON public.dms_files;
DROP POLICY IF EXISTS "DMS Files MAVI update" ON public.dms_files;
DROP POLICY IF EXISTS "DMS Files MAVI delete" ON public.dms_files;
DROP POLICY IF EXISTS "DMS Files MAVI insert" ON public.dms_files;
DROP POLICY IF EXISTS "DMS Files MAVI select" ON public.dms_files;

CREATE POLICY "DMS Files MAVI select" ON public.dms_files
  FOR SELECT
  USING (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND public.can_access_dms_file(id)
  );

CREATE POLICY "DMS Files MAVI insert" ON public.dms_files
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
  )
  WITH CHECK (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND public.is_mavi_employee_profile()
  );

CREATE POLICY "DMS Files MAVI delete" ON public.dms_files
  FOR DELETE
  USING (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND public.is_mavi_employee_profile()
  );

-- Tillatelser
DROP POLICY IF EXISTS "DMS Permissions Access" ON public.dms_permissions;
DROP POLICY IF EXISTS "DMS Permissions MAVI select" ON public.dms_permissions;
DROP POLICY IF EXISTS "DMS Permissions MAVI insert" ON public.dms_permissions;
DROP POLICY IF EXISTS "DMS Permissions MAVI delete" ON public.dms_permissions;

CREATE POLICY "DMS Permissions MAVI select" ON public.dms_permissions
  FOR SELECT
  USING (
    user_id = auth.uid()
    OR (SELECT role::text FROM public.profiles WHERE id = auth.uid()) IN ('admin', 'superadmin')
  );

CREATE POLICY "DMS Permissions MAVI insert" ON public.dms_permissions
  FOR INSERT
  WITH CHECK (
    (SELECT role::text FROM public.profiles WHERE id = auth.uid()) IN ('admin', 'superadmin', 'leder')
    OR user_id = auth.uid()
  );

CREATE POLICY "DMS Permissions MAVI delete" ON public.dms_permissions
  FOR DELETE
  USING (
    (SELECT role::text FROM public.profiles WHERE id = auth.uid()) IN ('admin', 'superadmin', 'leder')
    OR user_id = auth.uid()
  );
