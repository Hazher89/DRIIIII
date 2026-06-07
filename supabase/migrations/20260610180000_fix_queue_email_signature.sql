-- Avvik-lagring feilet: queue_email_if_allowed kalte queue_email med feil signatur.
-- Feil: queue_email(uuid, text×5, uuid×3) — mangler p_description (text) før uuid.

DROP FUNCTION IF EXISTS public.queue_email(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, UUID);
DROP FUNCTION IF EXISTS public.queue_email(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT, UUID, TEXT, UUID, UUID
);

CREATE OR REPLACE FUNCTION public.queue_email(
  p_company_id UUID,
  p_to_email TEXT,
  p_subject TEXT,
  p_body TEXT,
  p_category TEXT DEFAULT NULL,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id UUID DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_to_user_id UUID DEFAULT NULL,
  p_triggered_by_user_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_id UUID;
  v_email TEXT;
BEGIN
  v_email := trim(lower(coalesce(p_to_email, '')));
  IF v_email = '' OR position('@' IN v_email) < 2 THEN
    RETURN NULL;
  END IF;
  IF p_subject IS NULL OR length(trim(p_subject)) = 0 THEN
    RETURN NULL;
  END IF;
  IF p_body IS NULL OR length(trim(p_body)) = 0 THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.email_outbox (
    company_id, to_email, subject, body, category, reference_type, reference_id,
    description, to_user_id, triggered_by_user_id
  ) VALUES (
    p_company_id,
    v_email,
    left(trim(p_subject), 500),
    left(trim(p_body), 50000),
    p_category,
    p_reference_type,
    p_reference_id,
    p_description,
    p_to_user_id,
    COALESCE(p_triggered_by_user_id, auth.uid())
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.queue_email(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT, UUID, TEXT, UUID, UUID
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.queue_email(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT, UUID, TEXT, UUID, UUID
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.queue_email_if_allowed(
  p_company_id UUID,
  p_user_id UUID,
  p_to_email TEXT,
  p_subject TEXT,
  p_body TEXT,
  p_category TEXT,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id UUID DEFAULT NULL,
  p_setting_key TEXT DEFAULT 'general',
  p_description TEXT DEFAULT NULL,
  p_partner_scope BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_email TEXT;
BEGIN
  IF p_partner_scope THEN
    IF NOT public.company_partner_email_enabled(p_company_id, p_setting_key) THEN
      PERFORM public.log_notification_audit(
        p_company_id, 'email', p_category, p_setting_key,
        coalesce(p_to_email, ''), p_user_id, 'skipped', 'company_channel_off',
        coalesce(p_description, p_subject), NULL, NULL, NULL, p_reference_type, p_reference_id
      );
      RETURN NULL;
    END IF;
  ELSIF p_user_id IS NOT NULL THEN
    IF NOT public.profile_event_allows_email(p_company_id, p_user_id, p_setting_key) THEN
      PERFORM public.log_notification_audit(
        p_company_id, 'email', p_category, p_setting_key,
        coalesce(p_to_email, ''), p_user_id, 'skipped', 'profile_channel_off',
        coalesce(p_description, p_subject), NULL, NULL, NULL, p_reference_type, p_reference_id
      );
      RETURN NULL;
    END IF;
  ELSIF NOT public.company_email_enabled(p_company_id, p_setting_key) THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'email', p_category, p_setting_key,
      coalesce(p_to_email, ''), p_user_id, 'skipped', 'company_channel_off',
      coalesce(p_description, p_subject), NULL, NULL, NULL, p_reference_type, p_reference_id
    );
    RETURN NULL;
  END IF;

  v_email := COALESCE(
    (SELECT email FROM public.profiles WHERE id = p_user_id),
    p_to_email
  );

  IF coalesce(v_email, '') = '' THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'email', p_category, p_setting_key,
      '', p_user_id, 'skipped', 'missing_email',
      coalesce(p_description, p_subject), NULL, NULL, NULL, p_reference_type, p_reference_id
    );
    RETURN NULL;
  END IF;

  v_id := public.queue_email(
    p_company_id,
    v_email,
    p_subject,
    p_body,
    p_category,
    p_reference_type,
    p_reference_id,
    p_description,
    p_user_id,
    auth.uid()
  );

  IF v_id IS NOT NULL THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'email', p_category, p_setting_key,
      v_email, p_user_id, 'queued', NULL,
      coalesce(p_description, p_subject), NULL, v_id, NULL, p_reference_type, p_reference_id
    );
  END IF;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.queue_email_if_allowed TO authenticated, service_role;
