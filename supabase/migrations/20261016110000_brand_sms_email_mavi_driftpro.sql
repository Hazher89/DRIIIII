-- Alltid merk SMS-tekst med MAVI/DriftPro ved køing.

CREATE OR REPLACE FUNCTION public.queue_sms(
  p_company_id UUID,
  p_to_phone TEXT,
  p_message TEXT,
  p_category TEXT DEFAULT NULL,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id UUID DEFAULT NULL,
  p_to_user_id UUID DEFAULT NULL,
  p_triggered_by_user_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized TEXT;
  new_id UUID;
  v_msg TEXT;
BEGIN
  normalized := public.normalize_phone_no(p_to_phone);
  IF normalized IS NULL THEN
    RETURN NULL;
  END IF;
  IF p_message IS NULL OR length(trim(p_message)) = 0 THEN
    RETURN NULL;
  END IF;

  v_msg := trim(p_message);
  IF v_msg ~* '^mavi\s*/\s*driftpro\b' THEN
    v_msg := regexp_replace(v_msg, '^mavi\s*/\s*driftpro\b\s*:?\s*', 'MAVI/DriftPro: ', 'i');
  ELSIF v_msg ~* '^driftpro\b\s*:' THEN
    v_msg := regexp_replace(v_msg, '^driftpro\b\s*:\s*', 'MAVI/DriftPro: ', 'i');
  ELSIF v_msg ~* '^mavi\b\s*:' AND v_msg !~* '^mavi\s*/\s*driftpro' THEN
    v_msg := regexp_replace(v_msg, '^mavi\b\s*:\s*', 'MAVI/DriftPro: ', 'i');
  ELSE
    v_msg := 'MAVI/DriftPro: ' || v_msg;
  END IF;

  INSERT INTO public.sms_outbox (
    company_id, to_phone, message, category, reference_type, reference_id,
    to_user_id, triggered_by_user_id
  ) VALUES (
    p_company_id,
    normalized,
    left(v_msg, 1071),
    p_category,
    p_reference_type,
    p_reference_id,
    p_to_user_id,
    COALESCE(p_triggered_by_user_id, auth.uid())
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;
