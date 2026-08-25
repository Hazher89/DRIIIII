-- DriftPro kunnskaps-assistent: remote av/på uten app-update.

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS assistant_enabled boolean NOT NULL DEFAULT false;

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS assistant_title text;

COMMENT ON COLUMN public.companies.assistant_enabled IS
  'Vis flytende DriftPro-assistent (chat) for alle i selskapet. Styres av admin uten app-oppdatering.';

COMMENT ON COLUMN public.companies.assistant_title IS
  'Valgfri tittel på assistenten (standard: Spør DriftPro).';

CREATE OR REPLACE FUNCTION public.set_company_assistant_enabled(
  p_enabled boolean,
  p_title text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company uuid;
  v_role text;
  v_title text;
BEGIN
  SELECT company_id, role::text
    INTO v_company, v_role
  FROM public.profiles
  WHERE id = auth.uid();

  IF v_company IS NULL THEN
    RAISE EXCEPTION 'Ingen bedrift for bruker';
  END IF;

  IF v_role IS NULL OR v_role NOT IN ('admin', 'superadmin') THEN
    RAISE EXCEPTION 'Kun administrator kan styre DriftPro-assistenten';
  END IF;

  v_title := nullif(trim(coalesce(p_title, '')), '');

  UPDATE public.companies
  SET
    assistant_enabled = coalesce(p_enabled, false),
    assistant_title = COALESCE(v_title, assistant_title),
    updated_at = now()
  WHERE id = v_company;

  RETURN jsonb_build_object(
    'ok', true,
    'assistant_enabled', p_enabled,
    'assistant_title', (
      SELECT assistant_title FROM public.companies WHERE id = v_company
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_company_assistant_enabled(boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_company_assistant_enabled(boolean, text) TO authenticated;
