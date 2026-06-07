-- Tøm SMS/e-post/audit-logg for bedriften (superadmin eller varsel-tilgang).

CREATE OR REPLACE FUNCTION public.user_can_clear_notification_logs()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_settings JSONB;
  v_role TEXT;
BEGIN
  SELECT access_settings, role::text
  INTO v_settings, v_role
  FROM public.profiles
  WHERE id = auth.uid();

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_role = 'superadmin' THEN
    RETURN true;
  END IF;

  RETURN COALESCE((v_settings ->> 'varsler')::boolean, false);
END;
$$;

GRANT EXECUTE ON FUNCTION public.user_can_clear_notification_logs() TO authenticated;

CREATE OR REPLACE FUNCTION public.clear_company_notification_logs(
  p_sms BOOLEAN DEFAULT TRUE,
  p_email BOOLEAN DEFAULT TRUE,
  p_audit BOOLEAN DEFAULT TRUE,
  p_only_queued BOOLEAN DEFAULT FALSE,
  p_partner_scope_only BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_sms BIGINT := 0;
  v_email BIGINT := 0;
  v_audit BIGINT := 0;
BEGIN
  IF NOT public.user_can_clear_notification_logs() THEN
    RAISE EXCEPTION 'Ingen tilgang til å tømme varsel-logg';
  END IF;

  SELECT company_id INTO v_company_id
  FROM public.profiles
  WHERE id = auth.uid();

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke bedrift';
  END IF;

  IF p_sms THEN
    DELETE FROM public.sms_outbox o
    WHERE o.company_id = v_company_id
      AND (NOT p_partner_scope_only OR public.is_partner_scope_sms(o.category, o.reference_type))
      AND (
        NOT p_only_queued
        OR (o.sent_at IS NULL AND (o.error_message IS NULL OR o.attempts < 3))
      );
    GET DIAGNOSTICS v_sms = ROW_COUNT;
  END IF;

  IF p_email THEN
    DELETE FROM public.email_outbox o
    WHERE o.company_id = v_company_id
      AND (NOT p_partner_scope_only OR public.is_partner_scope_email_category(o.category))
      AND (
        NOT p_only_queued
        OR (o.sent_at IS NULL AND (o.error_message IS NULL OR o.attempts < 3))
      );
    GET DIAGNOSTICS v_email = ROW_COUNT;
  END IF;

  IF p_audit THEN
    DELETE FROM public.notification_audit a
    WHERE a.company_id = v_company_id
      AND (
        NOT p_partner_scope_only
        OR COALESCE(a.category, '') LIKE 'partner%'
        OR COALESCE(a.setting_key, '') LIKE 'partner%'
      );
    GET DIAGNOSTICS v_audit = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object(
    'sms_deleted', v_sms,
    'email_deleted', v_email,
    'audit_deleted', v_audit
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.clear_company_notification_logs(
  BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN
) TO authenticated;
