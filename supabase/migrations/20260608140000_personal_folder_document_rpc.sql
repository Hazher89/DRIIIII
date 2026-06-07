-- Personalmappe: ansatt kan laste opp egne dokumenter og oppdatere metadata.

CREATE OR REPLACE FUNCTION public.upload_own_personal_document(
  p_document_type TEXT,
  p_title TEXT,
  p_file_url TEXT,
  p_file_name TEXT DEFAULT NULL,
  p_file_size INTEGER DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_expires_at DATE DEFAULT NULL,
  p_tags TEXT[] DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_company UUID;
BEGIN
  SELECT company_id INTO v_company FROM public.profiles WHERE id = auth.uid();
  IF v_company IS NULL THEN
    RAISE EXCEPTION 'Ingen bedrift';
  END IF;

  INSERT INTO public.documents (
    user_id, company_id, document_type, title, description,
    file_url, file_name, file_size, expires_at,
    uploaded_by, employee_visible, tags, updated_at
  ) VALUES (
    auth.uid(), v_company, p_document_type::document_type, p_title, p_description,
    p_file_url, p_file_name, p_file_size, p_expires_at,
    auth.uid(), true, COALESCE(p_tags, '{}'), now()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_personal_document(
  p_id UUID,
  p_title TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_document_type TEXT DEFAULT NULL,
  p_expires_at DATE DEFAULT NULL,
  p_file_url TEXT DEFAULT NULL,
  p_file_name TEXT DEFAULT NULL,
  p_file_size INTEGER DEFAULT NULL,
  p_tags TEXT[] DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
  v_doc public.documents%ROWTYPE;
BEGIN
  SELECT * INTO v_doc FROM public.documents WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Dokument ikke funnet';
  END IF;

  SELECT role::text INTO v_role FROM public.profiles WHERE id = auth.uid();

  IF v_doc.user_id <> auth.uid()
     AND COALESCE(v_role, '') NOT IN ('superadmin', 'admin', 'leder') THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  UPDATE public.documents SET
    title = COALESCE(p_title, title),
    description = COALESCE(p_description, description),
    document_type = COALESCE(p_document_type::document_type, document_type),
    expires_at = COALESCE(p_expires_at, expires_at),
    file_url = COALESCE(p_file_url, file_url),
    file_name = COALESCE(p_file_name, file_name),
    file_size = COALESCE(p_file_size, file_size),
    tags = COALESCE(p_tags, tags),
    updated_at = now()
  WHERE id = p_id;

  RETURN p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upload_own_personal_document TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_personal_document TO authenticated;
