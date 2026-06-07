-- DMS opplasting i felles mapper: forenkle INSERT RLS, bruk mappens company_id.

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
  v_role TEXT;
  v_folder_company UUID;
BEGIN
  IF v_uid IS NULL OR p_company_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT role::text INTO v_role FROM public.profiles WHERE id = v_uid;

  IF v_role IN ('admin', 'superadmin', 'leder') THEN
    IF p_folder_id IS NULL THEN
      RETURN p_company_id IS NOT DISTINCT FROM public.get_user_company_id()
        OR p_company_id IS NOT DISTINCT FROM public.get_bootstrap_company_id();
    END IF;
    SELECT f.company_id INTO v_folder_company
    FROM public.dms_folders f WHERE f.id = p_folder_id;
    IF NOT FOUND OR v_folder_company IS DISTINCT FROM p_company_id THEN
      RETURN false;
    END IF;
    RETURN public.can_access_dms_folder(p_folder_id);
  END IF;

  IF NOT public.is_mavi_employee_profile(v_uid) THEN
    RETURN false;
  END IF;

  IF p_folder_id IS NULL THEN
    RETURN p_company_id IS NOT DISTINCT FROM COALESCE(
      public.get_user_company_id(),
      public.get_bootstrap_company_id()
    );
  END IF;

  SELECT f.company_id INTO v_folder_company
  FROM public.dms_folders f
  WHERE f.id = p_folder_id;

  IF NOT FOUND OR v_folder_company IS DISTINCT FROM p_company_id THEN
    RETURN false;
  END IF;

  RETURN public.can_access_dms_folder(p_folder_id);
END;
$$;

DROP POLICY IF EXISTS "DMS Files MAVI insert" ON public.dms_files;

CREATE POLICY "DMS Files MAVI insert" ON public.dms_files
  FOR INSERT
  WITH CHECK (
    created_by = auth.uid()
    AND public.can_insert_dms_file(folder_id, company_id)
  );

-- Synk filers company_id til mappen de ligger i (legacy/import)
UPDATE public.dms_files df
SET company_id = f.company_id
FROM public.dms_folders f
WHERE df.folder_id = f.id
  AND df.company_id IS DISTINCT FROM f.company_id;
