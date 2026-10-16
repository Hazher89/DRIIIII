-- Apple Custom Apps redeem-code pool + send Apple/Google app-download SMS.

CREATE TABLE IF NOT EXISTS public.app_store_redeem_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL,
  redeem_url TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'available'
    CHECK (status IN ('available', 'used', 'void')),
  batch_label TEXT,
  used_at TIMESTAMPTZ,
  used_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  sent_to_phone TEXT,
  sms_outbox_id UUID,
  ref_type TEXT,
  ref_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT app_store_redeem_codes_code_unique UNIQUE (code)
);

CREATE INDEX IF NOT EXISTS idx_app_store_redeem_codes_available
  ON public.app_store_redeem_codes (status, created_at)
  WHERE status = 'available';

CREATE INDEX IF NOT EXISTS idx_app_store_redeem_codes_used_at
  ON public.app_store_redeem_codes (used_at DESC NULLS LAST)
  WHERE status = 'used';

ALTER TABLE public.app_store_redeem_codes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_store_redeem_codes_select_admin ON public.app_store_redeem_codes;
CREATE POLICY app_store_redeem_codes_select_admin
  ON public.app_store_redeem_codes
  FOR SELECT
  TO authenticated
  USING (
    public.get_user_role() IN (
      'admin'::public.user_role,
      'superadmin'::public.user_role,
      'leder'::public.user_role
    )
  );

GRANT SELECT ON public.app_store_redeem_codes TO authenticated;
GRANT ALL ON public.app_store_redeem_codes TO service_role;

CREATE OR REPLACE FUNCTION public.app_store_redeem_codes_stats()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  RETURN jsonb_build_object(
    'available', (
      SELECT count(*)::int FROM public.app_store_redeem_codes WHERE status = 'available'
    ),
    'used', (
      SELECT count(*)::int FROM public.app_store_redeem_codes WHERE status = 'used'
    ),
    'void', (
      SELECT count(*)::int FROM public.app_store_redeem_codes WHERE status = 'void'
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.app_store_redeem_codes_stats() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.send_app_download_sms(
  p_platform TEXT,
  p_phone TEXT,
  p_display_name TEXT DEFAULT NULL,
  p_username TEXT DEFAULT NULL,
  p_password TEXT DEFAULT NULL,
  p_ref_type TEXT DEFAULT NULL,
  p_ref_id UUID DEFAULT NULL,
  p_user_id UUID DEFAULT NULL,
  p_company_id UUID DEFAULT '00000000-0000-0000-0000-000000000000'::uuid
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_platform TEXT := lower(trim(coalesce(p_platform, '')));
  v_phone TEXT;
  v_first TEXT;
  v_username TEXT := nullif(trim(coalesce(p_username, '')), '');
  v_password TEXT := coalesce(nullif(trim(coalesce(p_password, '')), ''), '000000');
  v_code_row public.app_store_redeem_codes%ROWTYPE;
  v_link TEXT;
  v_msg TEXT;
  v_sms_id UUID;
  v_category TEXT;
  v_remaining INT;
  v_role TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  v_role := coalesce(public.get_user_role()::text, '');
  IF v_role NOT IN ('admin', 'superadmin', 'leder', 'ansatt') THEN
    RAISE EXCEPTION 'Mangler tilgang til å sende app-lenke';
  END IF;

  IF v_platform NOT IN ('apple', 'google') THEN
    RAISE EXCEPTION 'Ugyldig plattform (apple/google)';
  END IF;

  v_phone := public.normalize_phone_no(p_phone);
  IF v_phone IS NULL THEN
    RAISE EXCEPTION 'Ugyldig telefonnummer';
  END IF;

  v_first := split_part(trim(coalesce(p_display_name, '')), ' ', 1);
  IF v_first = '' THEN
    v_first := 'der';
  END IF;

  IF v_platform = 'apple' THEN
    SELECT *
    INTO v_code_row
    FROM public.app_store_redeem_codes
    WHERE status = 'available'
    ORDER BY created_at ASC, code ASC
    FOR UPDATE SKIP LOCKED
    LIMIT 1;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Ingen ledige Apple-koder igjen';
    END IF;

    v_link := v_code_row.redeem_url;
    v_category := 'app_download_apple';

    v_msg :=
      'Hei ' || v_first || E'!\n\n'
      || E'DriftPro er klar.\n\n'
      || E'Last ned appen:\niPhone (personlig engangskode):\n'
      || v_link || E'\n\n';
  ELSE
    v_link := 'https://play.google.com/store/apps/details?id=no.driftpro.driftpro';
    v_category := 'app_download_google';

    v_msg :=
      'Hei ' || v_first || E'!\n\n'
      || E'DriftPro er klar.\n\n'
      || E'Last ned appen:\nAndroid:\n'
      || v_link || E'\n\n';
  END IF;

  IF v_username IS NOT NULL THEN
    v_msg := v_msg
      || E'Logg inn med:\n'
      || 'Brukernavn: ' || v_username || E'\n'
      || 'Passord: ' || v_password || E'\n\n'
      || E'Du kan enkelt endre passordet etter innlogging under Profil.\n\n'
      || 'Velkommen!';
  ELSE
    v_msg := v_msg || 'Logg inn i DriftPro med ditt brukernavn. Velkommen!';
  END IF;

  v_sms_id := public.queue_sms(
    coalesce(p_company_id, '00000000-0000-0000-0000-000000000000'::uuid),
    v_phone,
    v_msg,
    v_category,
    p_ref_type,
    p_ref_id,
    p_user_id,
    auth.uid()
  );

  IF v_sms_id IS NULL THEN
    RAISE EXCEPTION 'Kunne ikke køe SMS';
  END IF;

  IF v_platform = 'apple' THEN
    UPDATE public.app_store_redeem_codes
    SET
      status = 'used',
      used_at = now(),
      used_by = auth.uid(),
      sent_to_phone = v_phone,
      sms_outbox_id = v_sms_id,
      ref_type = p_ref_type,
      ref_id = p_ref_id
    WHERE id = v_code_row.id;
  END IF;

  SELECT count(*)::int INTO v_remaining
  FROM public.app_store_redeem_codes
  WHERE status = 'available';

  RETURN jsonb_build_object(
    'sms_id', v_sms_id,
    'platform', v_platform,
    'code', CASE WHEN v_platform = 'apple' THEN v_code_row.code ELSE NULL END,
    'redeem_url', CASE WHEN v_platform = 'apple' THEN v_code_row.redeem_url ELSE v_link END,
    'remaining_codes', v_remaining,
    'to_phone', v_phone
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_app_download_sms(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, UUID, UUID, UUID
) TO authenticated, service_role;

COMMENT ON TABLE public.app_store_redeem_codes IS
  'Apple Custom Apps redeem codes. Marked used atomically when send_app_download_sms(apple) runs.';
COMMENT ON FUNCTION public.send_app_download_sms IS
  'Send Apple (unique redeem) or Google Play download SMS; Apple codes consumed once.';
