-- Én FCM-token = én aktiv bruker. Ved innlogging overtas token;
-- ved utlogging må deaktivering skje mens auth.uid() fortsatt finnes (app-side).

CREATE OR REPLACE FUNCTION public.upsert_push_device(
  p_fcm_token TEXT,
  p_platform TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  tok TEXT := trim(coalesce(p_fcm_token, ''));
BEGIN
  IF uid IS NULL OR tok = '' THEN
    RETURN;
  END IF;

  -- Frigjør token fra andre profiler (samme telefon, annen innlogging).
  UPDATE public.user_push_devices
  SET is_active = false
  WHERE fcm_token = tok
    AND profile_id IS DISTINCT FROM uid
    AND is_active = true;

  UPDATE public.profiles
  SET fcm_token = NULL
  WHERE fcm_token = tok
    AND id IS DISTINCT FROM uid;

  INSERT INTO public.user_push_devices (profile_id, fcm_token, platform, last_seen_at, is_active)
  VALUES (uid, tok, nullif(trim(coalesce(p_platform, '')), ''), now(), true)
  ON CONFLICT (profile_id, fcm_token) DO UPDATE SET
    platform = coalesce(excluded.platform, public.user_push_devices.platform),
    last_seen_at = now(),
    is_active = true;

  UPDATE public.profiles
  SET fcm_token = tok
  WHERE id = uid;
END;
$$;

CREATE OR REPLACE FUNCTION public.deactivate_push_devices()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.user_push_devices
  SET is_active = false
  WHERE profile_id = uid;

  UPDATE public.profiles
  SET fcm_token = NULL
  WHERE id = uid;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_push_device(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deactivate_push_devices() TO authenticated;

COMMENT ON FUNCTION public.upsert_push_device(TEXT, TEXT) IS
  'Registrerer FCM-token for innlogget bruker og deaktiverer samme token for andre profiler.';
