-- DMS opplasting: fiks company_id-mismatch, oppretter-tilgang og robust INSERT RLS.

-- Koble interne profiler uten company_id til bootstrap-selskap
UPDATE public.profiles p
SET company_id = public.get_bootstrap_company_id()
WHERE p.company_id IS NULL
  AND p.partner_id IS NULL
  AND COALESCE(p.role::text, 'ansatt') <> 'samarbeidspartner'
  AND public.get_bootstrap_company_id() IS NOT NULL;

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

  v_company := COALESCE(public.get_user_company_id(), public.get_bootstrap_company_id());

  -- Opplaster ser alltid egen fil (viktig for INSERT … RETURNING)
  IF v_file.created_by = auth.uid()
     AND v_company IS NOT NULL
     AND v_file.company_id = v_company THEN
    RETURN true;
  END IF;

  IF v_file.company_id IS DISTINCT FROM v_company THEN
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
  v_company UUID;
  v_role TEXT;
BEGIN
  IF v_uid IS NULL OR p_company_id IS NULL THEN
    RETURN false;
  END IF;

  v_company := COALESCE(public.get_user_company_id(), public.get_bootstrap_company_id());
  IF v_company IS NULL OR p_company_id IS DISTINCT FROM v_company THEN
    RETURN false;
  END IF;

  SELECT role::text INTO v_role FROM public.profiles WHERE id = v_uid;

  IF v_role IN ('admin', 'superadmin', 'leder') THEN
    IF p_folder_id IS NOT NULL AND NOT EXISTS (
      SELECT 1
      FROM public.dms_folders f
      WHERE f.id = p_folder_id
        AND f.company_id = v_company
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
      AND f.company_id = v_company
  ) THEN
    RETURN false;
  END IF;

  RETURN public.can_access_dms_folder(p_folder_id);
END;
$$;

-- INSERT-policy: bruk get_user_company_id (ikke subquery som kan gi NULL-mismatch)
DROP POLICY IF EXISTS "DMS Files MAVI insert" ON public.dms_files;

CREATE POLICY "DMS Files MAVI insert" ON public.dms_files
  FOR INSERT
  WITH CHECK (
    company_id IS NOT DISTINCT FROM COALESCE(
      public.get_user_company_id(),
      public.get_bootstrap_company_id()
    )
    AND public.can_insert_dms_file(folder_id, company_id)
  );

GRANT EXECUTE ON FUNCTION public.get_user_company_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_bootstrap_company_id() TO authenticated;
