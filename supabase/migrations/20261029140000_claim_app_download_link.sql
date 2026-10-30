-- Claim Apple/Google app download link without SMS (for WhatsApp / clipboard).
-- Apple: consumes one redeem code. Google: returns public Play Store URL.

CREATE OR REPLACE FUNCTION public.claim_app_download_link(
  p_platform TEXT,
  p_phone TEXT DEFAULT NULL,
  p_ref_type TEXT DEFAULT NULL,
  p_ref_id UUID DEFAULT NULL,
  p_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_platform TEXT := lower(trim(coalesce(p_platform, '')));
  v_phone TEXT;
  v_code_row public.app_store_redeem_codes%ROWTYPE;
  v_link TEXT;
  v_remaining INT;
  v_role TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  v_role := coalesce(public.get_user_role()::text, '');
  IF v_role NOT IN ('admin', 'superadmin', 'leder', 'ansatt') THEN
    RAISE EXCEPTION 'Mangler tilgang til å hente app-lenke';
  END IF;

  IF v_platform NOT IN ('apple', 'google') THEN
    RAISE EXCEPTION 'Ugyldig plattform (apple/google)';
  END IF;

  IF p_phone IS NOT NULL AND trim(p_phone) <> '' THEN
    v_phone := public.normalize_phone_no(p_phone);
  ELSE
    v_phone := NULL;
  END IF;

  IF v_platform = 'google' THEN
    v_link := 'https://play.google.com/store/apps/details?id=no.driftpro.driftpro';
    SELECT count(*)::int INTO v_remaining
    FROM public.app_store_redeem_codes
    WHERE status = 'available';

    RETURN jsonb_build_object(
      'platform', 'google',
      'code', NULL,
      'redeem_url', v_link,
      'remaining_codes', v_remaining,
      'to_phone', v_phone,
      'consumed', false
    );
  END IF;

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

  UPDATE public.app_store_redeem_codes
  SET
    status = 'used',
    used_at = now(),
    used_by = auth.uid(),
    sent_to_phone = v_phone,
    ref_type = coalesce(nullif(trim(p_ref_type), ''), 'clipboard_whatsapp'),
    ref_id = p_ref_id
  WHERE id = v_code_row.id;

  SELECT count(*)::int INTO v_remaining
  FROM public.app_store_redeem_codes
  WHERE status = 'available';

  RETURN jsonb_build_object(
    'platform', 'apple',
    'code', v_code_row.code,
    'redeem_url', v_code_row.redeem_url,
    'remaining_codes', v_remaining,
    'to_phone', v_phone,
    'consumed', true,
    'note', nullif(trim(coalesce(p_note, '')), '')
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_app_download_link(
  TEXT, TEXT, TEXT, UUID, TEXT
) TO authenticated, service_role;

COMMENT ON FUNCTION public.claim_app_download_link IS
  'Returner app-lenke for WhatsApp/utklippstavle. Apple-kode markeres brukt; Google er offentlig Play-lenke.';
