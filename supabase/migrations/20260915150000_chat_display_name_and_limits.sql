-- Chat-visningsnavn (valgfritt) + begrensning: 1 endring / 30 dager for vanlige brukere.
-- Superadmin kan endre så ofte de vil (via egen RPC).

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS chat_display_name TEXT,
  ADD COLUMN IF NOT EXISTS chat_display_name_changed_at TIMESTAMPTZ;

COMMENT ON COLUMN public.profiles.chat_display_name IS
  'Valgfritt visningsnavn i chat. Fallback: full_name.';
COMMENT ON COLUMN public.profiles.chat_display_name_changed_at IS
  'Sist brukeren selv endret chat_display_name (rate limit).';

CREATE OR REPLACE FUNCTION public.chat_profile_display_name(p_full_name TEXT, p_chat_display_name TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT coalesce(nullif(trim(p_chat_display_name), ''), nullif(trim(p_full_name), ''), 'Bruker');
$$;

CREATE OR REPLACE FUNCTION public.set_my_chat_display_name(p_name TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_name TEXT := nullif(trim(p_name), '');
  v_prev TIMESTAMPTZ;
  v_next TIMESTAMPTZ;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  IF v_name IS NULL OR char_length(v_name) < 2 THEN
    RAISE EXCEPTION 'Navnet må være minst 2 tegn';
  END IF;
  IF char_length(v_name) > 40 THEN
    RAISE EXCEPTION 'Navnet kan maks være 40 tegn';
  END IF;

  SELECT chat_display_name_changed_at INTO v_prev
  FROM public.profiles WHERE id = v_uid;

  IF v_prev IS NOT NULL AND v_prev > now() - interval '30 days' THEN
    v_next := v_prev + interval '30 days';
    RAISE EXCEPTION 'Du kan bare endre chat-navn én gang per måned. Neste gang: %',
      to_char(v_next AT TIME ZONE 'Europe/Oslo', 'DD.MM.YYYY');
  END IF;

  UPDATE public.profiles
  SET chat_display_name = v_name,
      chat_display_name_changed_at = now()
  WHERE id = v_uid;

  RETURN jsonb_build_object(
    'ok', true,
    'chat_display_name', v_name,
    'changed_at', now()
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_chat_display_name(
  p_user_id UUID,
  p_name TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_name TEXT := nullif(trim(p_name), '');
  v_role TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = v_uid;
  IF lower(coalesce(v_role, '')) <> 'superadmin' THEN
    RAISE EXCEPTION 'Kun superadmin kan endre andres chat-navn';
  END IF;

  IF v_name IS NULL OR char_length(v_name) < 2 THEN
    RAISE EXCEPTION 'Navnet må være minst 2 tegn';
  END IF;
  IF char_length(v_name) > 40 THEN
    RAISE EXCEPTION 'Navnet kan maks være 40 tegn';
  END IF;

  UPDATE public.profiles
  SET chat_display_name = v_name
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bruker ikke funnet';
  END IF;

  -- Superadmin-endring nullstiller ikke rate-limit for brukeren.
  RETURN jsonb_build_object(
    'ok', true,
    'user_id', p_user_id,
    'chat_display_name', v_name
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_my_chat_display_name(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_chat_display_name(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_profile_display_name(TEXT, TEXT) TO authenticated;
