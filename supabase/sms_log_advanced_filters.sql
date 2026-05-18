-- Utvidet SMS-logg: dato, mottaker, avsender, telefon
-- Kjør etter sms_log_admin.sql

CREATE OR REPLACE FUNCTION public.list_company_sms_log(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0,
  p_search TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_from_date TIMESTAMPTZ DEFAULT NULL,
  p_to_date TIMESTAMPTZ DEFAULT NULL,
  p_recipient TEXT DEFAULT NULL,
  p_sender TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT NULL
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
  delivery_status TEXT,
  sender_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
    COALESCE(pt.full_name, 'System (automatisk)') AS triggered_by_name,
    o.triggered_by_user_id,
    CASE
      WHEN o.sent_at IS NOT NULL THEN 'sendt'
      WHEN o.error_message IS NOT NULL AND o.attempts >= 3 THEN 'feilet'
      WHEN o.error_message IS NOT NULL THEN 'feil'
      ELSE 'i_ko'
    END AS delivery_status,
    'Mavi'::text AS sender_name
  FROM public.sms_outbox o
  LEFT JOIN public.profiles pr ON pr.id = o.to_user_id
  LEFT JOIN public.profiles pt ON pt.id = o.triggered_by_user_id
  WHERE o.company_id = v_company_id
    AND (p_category IS NULL OR o.category = p_category)
    AND (p_from_date IS NULL OR o.created_at >= p_from_date)
    AND (p_to_date IS NULL OR o.created_at <= p_to_date)
    AND (
      p_status IS NULL
      OR (p_status = 'sendt' AND o.sent_at IS NOT NULL)
      OR (p_status = 'i_ko' AND o.sent_at IS NULL AND (o.error_message IS NULL OR o.attempts < 3))
      OR (p_status = 'feilet' AND o.sent_at IS NULL AND o.attempts >= 3)
    )
    AND (
      p_phone IS NULL OR length(trim(p_phone)) = 0
      OR o.to_phone ILIKE '%' || regexp_replace(trim(p_phone), '[^0-9+]', '', 'g') || '%'
    )
    AND (
      p_recipient IS NULL OR length(trim(p_recipient)) = 0
      OR COALESCE(pr.full_name, '') ILIKE '%' || trim(p_recipient) || '%'
      OR o.to_phone ILIKE '%' || trim(p_recipient) || '%'
    )
    AND (
      p_sender IS NULL OR length(trim(p_sender)) = 0
      OR COALESCE(pt.full_name, '') ILIKE '%' || trim(p_sender) || '%'
      OR 'Mavi' ILIKE '%' || trim(p_sender) || '%'
    )
    AND (
      p_search IS NULL OR length(trim(p_search)) = 0
      OR o.message ILIKE '%' || trim(p_search) || '%'
      OR COALESCE(o.category, '') ILIKE '%' || trim(p_search) || '%'
    )
  ORDER BY o.created_at DESC
  LIMIT greatest(p_limit, 1)
  OFFSET greatest(p_offset, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.count_company_sms_log(
  p_search TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_from_date TIMESTAMPTZ DEFAULT NULL,
  p_to_date TIMESTAMPTZ DEFAULT NULL,
  p_recipient TEXT DEFAULT NULL,
  p_sender TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT NULL
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
  FROM public.sms_outbox o
  LEFT JOIN public.profiles pr ON pr.id = o.to_user_id
  LEFT JOIN public.profiles pt ON pt.id = o.triggered_by_user_id
  WHERE o.company_id = v_company_id
    AND (p_category IS NULL OR o.category = p_category)
    AND (p_from_date IS NULL OR o.created_at >= p_from_date)
    AND (p_to_date IS NULL OR o.created_at <= p_to_date)
    AND (
      p_status IS NULL
      OR (p_status = 'sendt' AND o.sent_at IS NOT NULL)
      OR (p_status = 'i_ko' AND o.sent_at IS NULL AND (o.error_message IS NULL OR o.attempts < 3))
      OR (p_status = 'feilet' AND o.sent_at IS NULL AND o.attempts >= 3)
    )
    AND (
      p_phone IS NULL OR length(trim(p_phone)) = 0
      OR o.to_phone ILIKE '%' || regexp_replace(trim(p_phone), '[^0-9+]', '', 'g') || '%'
    )
    AND (
      p_recipient IS NULL OR length(trim(p_recipient)) = 0
      OR COALESCE(pr.full_name, '') ILIKE '%' || trim(p_recipient) || '%'
      OR o.to_phone ILIKE '%' || trim(p_recipient) || '%'
    )
    AND (
      p_sender IS NULL OR length(trim(p_sender)) = 0
      OR COALESCE(pt.full_name, '') ILIKE '%' || trim(p_sender) || '%'
      OR 'Mavi' ILIKE '%' || trim(p_sender) || '%'
    )
    AND (
      p_search IS NULL OR length(trim(p_search)) = 0
      OR o.message ILIKE '%' || trim(p_search) || '%'
      OR COALESCE(o.category, '') ILIKE '%' || trim(p_search) || '%'
    );

  RETURN c;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_company_sms_log(INT, INT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.count_company_sms_log(TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT) TO authenticated;
