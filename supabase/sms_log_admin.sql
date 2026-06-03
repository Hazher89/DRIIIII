-- SMS-logg for superadmin (profil) + utvidet metadata
-- Kjør etter sms_outbox_sveve.sql og sms_smart_notifications.sql

ALTER TABLE public.sms_outbox
  ADD COLUMN IF NOT EXISTS to_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS triggered_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_sms_outbox_company_created ON public.sms_outbox(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sms_outbox_to_user ON public.sms_outbox(to_user_id);

-- Utvidet kø (behold bakoverkompatibilitet via defaults)
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
BEGIN
  normalized := public.normalize_phone_no(p_to_phone);
  IF normalized IS NULL THEN
    RETURN NULL;
  END IF;
  IF p_message IS NULL OR length(trim(p_message)) = 0 THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.sms_outbox (
    company_id, to_phone, message, category, reference_type, reference_id,
    to_user_id, triggered_by_user_id
  ) VALUES (
    p_company_id,
    normalized,
    left(trim(p_message), 1071),
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

GRANT EXECUTE ON FUNCTION public.queue_sms(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID, UUID) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.queue_sms_if_allowed(
  p_company_id UUID,
  p_user_id UUID,
  p_phone TEXT,
  p_message TEXT,
  p_category TEXT,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id UUID DEFAULT NULL,
  p_setting_key TEXT DEFAULT 'general'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.company_sms_enabled(p_company_id, p_setting_key) THEN
    RETURN;
  END IF;
  IF p_user_id IS NOT NULL AND NOT public.user_accepts_sms(p_user_id) THEN
    RETURN;
  END IF;
  PERFORM public.queue_sms(
    p_company_id,
    COALESCE(
      (SELECT phone_normalized FROM public.profiles WHERE id = p_user_id),
      p_phone
    ),
    p_message,
    p_category,
    p_reference_type,
    p_reference_id,
    p_user_id,
    auth.uid()
  );
END;
$$;

-- Superadmin: hent SMS-logg for eget firma
CREATE OR REPLACE FUNCTION public.list_company_sms_log(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0,
  p_search TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  created_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  to_phone TEXT,
  message TEXT,
  category TEXT,
  reference_type TEXT,
  reference_id UUID,
  error_message TEXT,
  attempts INT,
  sveve_message_id BIGINT,
  recipient_name TEXT,
  recipient_user_id UUID,
  triggered_by_name TEXT,
  triggered_by_user_id UUID,
  delivery_status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_company_id UUID;
  v_role TEXT;
BEGIN
  SELECT company_id, role::text INTO v_company_id, v_role
  FROM public.profiles WHERE id = auth.uid();

  IF v_role IS DISTINCT FROM 'superadmin' THEN
    RAISE EXCEPTION 'Kun superadmin har tilgang til SMS-logg';
  END IF;

  RETURN QUERY
  SELECT
    o.id,
    o.created_at,
    o.sent_at,
    o.to_phone,
    o.message,
    o.category,
    o.reference_type,
    o.reference_id,
    o.error_message,
    o.attempts,
    o.sveve_message_id,
    COALESCE(
      pr.full_name,
      (SELECT p2.full_name FROM public.profiles p2
       WHERE p2.phone_normalized = o.to_phone AND p2.company_id = v_company_id
       LIMIT 1),
      o.to_phone
    ) AS recipient_name,
    COALESCE(o.to_user_id,
      (SELECT p3.id FROM public.profiles p3
       WHERE p3.phone_normalized = o.to_phone AND p3.company_id = v_company_id
       LIMIT 1)
    ) AS recipient_user_id,
    COALESCE(pt.full_name, 'System (automatisk / Mavi)') AS triggered_by_name,
    o.triggered_by_user_id,
    CASE
      WHEN o.sent_at IS NOT NULL THEN 'sendt'
      WHEN o.error_message IS NOT NULL AND o.attempts >= 3 THEN 'feilet'
      WHEN o.error_message IS NOT NULL THEN 'feil'
      ELSE 'i_ko'
    END AS delivery_status
  FROM public.sms_outbox o
  LEFT JOIN public.profiles pr ON pr.id = o.to_user_id
  LEFT JOIN public.profiles pt ON pt.id = o.triggered_by_user_id
  WHERE o.company_id = v_company_id
    AND (p_category IS NULL OR o.category = p_category)
    AND (
      p_status IS NULL
      OR (p_status = 'sendt' AND o.sent_at IS NOT NULL)
      OR (p_status = 'i_ko' AND o.sent_at IS NULL AND (o.error_message IS NULL OR o.attempts < 3))
      OR (p_status = 'feilet' AND o.sent_at IS NULL AND o.attempts >= 3)
    )
    AND (
      p_search IS NULL OR length(trim(p_search)) = 0
      OR o.message ILIKE '%' || trim(p_search) || '%'
      OR o.to_phone ILIKE '%' || trim(p_search) || '%'
      OR COALESCE(pr.full_name, '') ILIKE '%' || trim(p_search) || '%'
      OR COALESCE(o.category, '') ILIKE '%' || trim(p_search) || '%'
    )
  ORDER BY o.created_at DESC
  LIMIT greatest(p_limit, 1)
  OFFSET greatest(p_offset, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_company_sms_log(INT, INT, TEXT, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.count_company_sms_log(
  p_search TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_role TEXT;
  c BIGINT;
BEGIN
  SELECT company_id, role::text INTO v_company_id, v_role
  FROM public.profiles WHERE id = auth.uid();
  IF v_role IS DISTINCT FROM 'superadmin' THEN
    RETURN 0;
  END IF;

  SELECT count(*)::bigint INTO c
  FROM public.list_company_sms_log(100000, 0, p_search, p_category, p_status);

  RETURN c;
END;
$$;

GRANT EXECUTE ON FUNCTION public.count_company_sms_log(TEXT, TEXT, TEXT) TO authenticated;
