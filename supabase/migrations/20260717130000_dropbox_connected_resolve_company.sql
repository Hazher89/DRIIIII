-- Dropbox: pålitelig «er koblet»-sjekk (samme bedrift som edge function).
-- Unngår at appen tror Dropbox er av, mens OAuth er lagret på bootstrap-bedriften.

CREATE OR REPLACE FUNCTION public.resolve_user_company_id(p_uid UUID DEFAULT auth.uid())
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID;
BEGIN
  IF p_uid IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT company_id INTO v_company
  FROM public.profiles
  WHERE id = p_uid;

  IF v_company IS NOT NULL THEN
    RETURN v_company;
  END IF;

  BEGIN
    SELECT public.get_bootstrap_company_id() INTO v_company;
  EXCEPTION
    WHEN OTHERS THEN
      v_company := NULL;
  END;

  IF v_company IS NOT NULL THEN
    RETURN v_company;
  END IF;

  SELECT company_id INTO v_company
  FROM public.departments
  WHERE company_id IS NOT NULL
  LIMIT 1;

  IF v_company IS NOT NULL THEN
    RETURN v_company;
  END IF;

  SELECT id INTO v_company FROM public.companies LIMIT 1;
  RETURN v_company;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_company_dropbox_connected()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID;
BEGIN
  v_company := public.resolve_user_company_id(auth.uid());
  IF v_company IS NULL THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.company_dropbox_connections c
    WHERE c.company_id = v_company
  );
END;
$$;

COMMENT ON FUNCTION public.is_company_dropbox_connected() IS
  'Sant når brukerens bedrift (profil/bootstrap) har Dropbox-tilkobling. Alle plattformer bruker dette ved opplasting.';

GRANT EXECUTE ON FUNCTION public.resolve_user_company_id(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_company_dropbox_connected() TO authenticated;
