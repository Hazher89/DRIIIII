-- Fiks DMS fil-opplasting: INSERT RLS med admin-bypass, mappe-tilgang og konsistent company-sjekk.

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
      AND COALESCE(p.is_active, true) = true
      AND (
        COALESCE(p.role::text, 'ansatt') IN ('admin', 'superadmin')
        OR (
          p.partner_id IS NULL
          AND COALESCE(p.role::text, 'ansatt') NOT IN ('samarbeidspartner')
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.can_insert_dms_file(
  p_folder_id UUID,
  p_company_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_profile_company UUID;
  v_role TEXT;
BEGIN
  IF v_uid IS NULL OR p_company_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT company_id, role::text
  INTO v_profile_company, v_role
  FROM public.profiles
  WHERE id = v_uid;

  IF v_profile_company IS NULL OR v_profile_company IS DISTINCT FROM p_company_id THEN
    RETURN false;
  END IF;

  IF v_role IN ('admin', 'superadmin') THEN
    IF p_folder_id IS NOT NULL AND NOT EXISTS (
      SELECT 1
      FROM public.dms_folders f
      WHERE f.id = p_folder_id
        AND f.company_id = p_company_id
    ) THEN
      RETURN false;
    END IF;
    RETURN true;
  END IF;

  IF NOT public.is_mavi_employee_profile(v_uid) THEN
    RETURN false;
  END IF;

  IF p_folder_id IS NULL THEN
    RETURN true;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.dms_folders f
    WHERE f.id = p_folder_id
      AND f.company_id = p_company_id
  ) THEN
    RETURN false;
  END IF;

  RETURN public.can_access_dms_folder(p_folder_id);
END;
$$;

REVOKE ALL ON FUNCTION public.can_insert_dms_file(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_insert_dms_file(UUID, UUID) TO authenticated;

-- Filer: sikre at INSERT-policy finnes og bruker can_insert_dms_file
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
  WITH CHECK (public.can_insert_dms_file(folder_id, company_id));

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
