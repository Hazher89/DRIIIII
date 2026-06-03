-- Fix Postgres 42702: RETURNS TABLE (id ...) shadows profiles.id in WHERE id = auth.uid()

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

CREATE OR REPLACE FUNCTION public.list_company_email_log(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0,
  p_search TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_from_date TIMESTAMPTZ DEFAULT NULL,
  p_to_date TIMESTAMPTZ DEFAULT NULL,
  p_recipient TEXT DEFAULT NULL,
  p_sender TEXT DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  created_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  to_email TEXT,
  subject TEXT,
  body TEXT,
  description TEXT,
  category TEXT,
  reference_type TEXT,
  reference_id UUID,
  error_message TEXT,
  attempts INT,
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
#variable_conflict use_column
DECLARE
  v_company_id UUID;
  v_role TEXT;
BEGIN
  SELECT company_id, role::text INTO v_company_id, v_role
  FROM public.profiles WHERE id = auth.uid();

  IF v_role IS DISTINCT FROM 'superadmin' THEN
    RAISE EXCEPTION 'Kun superadmin har tilgang til e-post-logg';
  END IF;

  RETURN QUERY
  SELECT
    o.id,
    o.created_at,
    o.sent_at,
    o.to_email,
    o.subject,
    o.body,
    o.description,
    o.category,
    o.reference_type,
    o.reference_id,
    o.error_message,
    o.attempts,
    COALESCE(pr.full_name, o.to_email) AS recipient_name,
    o.to_user_id AS recipient_user_id,
    COALESCE(pt.full_name, 'System (automatisk)') AS triggered_by_name,
    o.triggered_by_user_id,
    CASE
      WHEN o.sent_at IS NOT NULL THEN 'sendt'
      WHEN o.error_message IS NOT NULL AND o.attempts >= 3 THEN 'feilet'
      WHEN o.error_message IS NOT NULL THEN 'feil'
      ELSE 'i_ko'
    END AS delivery_status,
    'ikkesvar@driftpro.no'::text AS sender_name
  FROM public.email_outbox o
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
      p_recipient IS NULL OR length(trim(p_recipient)) = 0
      OR o.to_email ILIKE '%' || trim(p_recipient) || '%'
      OR pr.full_name ILIKE '%' || trim(p_recipient) || '%'
    )
    AND (
      p_sender IS NULL OR length(trim(p_sender)) = 0
      OR pt.full_name ILIKE '%' || trim(p_sender) || '%'
    )
    AND (
      p_search IS NULL OR length(trim(p_search)) = 0
      OR o.subject ILIKE '%' || trim(p_search) || '%'
      OR o.body ILIKE '%' || trim(p_search) || '%'
      OR o.description ILIKE '%' || trim(p_search) || '%'
      OR o.to_email ILIKE '%' || trim(p_search) || '%'
    )
  ORDER BY o.created_at DESC
  LIMIT greatest(p_limit, 1)
  OFFSET greatest(p_offset, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_notification_audit(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0,
  p_channel TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_partner_scope BOOLEAN DEFAULT NULL,
  p_from_date TIMESTAMPTZ DEFAULT NULL,
  p_to_date TIMESTAMPTZ DEFAULT NULL,
  p_search TEXT DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  created_at TIMESTAMPTZ,
  event_channel TEXT,
  category TEXT,
  setting_key TEXT,
  recipient TEXT,
  status TEXT,
  skip_reason TEXT,
  description TEXT,
  partner_name TEXT
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

  IF v_role IS DISTINCT FROM 'superadmin'
     AND NOT public.user_can_view_partner_sms_log() THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  RETURN QUERY
  SELECT
    a.id,
    a.created_at,
    a.event_channel,
    a.category,
    a.setting_key,
    a.recipient,
    a.status,
    a.skip_reason,
    a.description,
    p.name AS partner_name
  FROM public.notification_audit a
  LEFT JOIN public.partners p ON p.id = a.partner_id
  WHERE a.company_id = v_company_id
    AND (p_channel IS NULL OR a.event_channel = p_channel)
    AND (p_status IS NULL OR a.status = p_status)
    AND (p_category IS NULL OR a.category = p_category)
    AND (p_from_date IS NULL OR a.created_at >= p_from_date)
    AND (p_to_date IS NULL OR a.created_at <= p_to_date)
    AND (
      p_partner_scope IS NULL
      OR (p_partner_scope = true AND a.partner_id IS NOT NULL)
      OR (p_partner_scope = false AND a.partner_id IS NULL
          AND COALESCE(a.setting_key, '') NOT LIKE 'partner%'
          AND COALESCE(a.setting_key, '') NOT LIKE 'vehicle_rental%')
    )
    AND (
      p_search IS NULL OR length(trim(p_search)) = 0
      OR a.description ILIKE '%' || trim(p_search) || '%'
      OR a.recipient ILIKE '%' || trim(p_search) || '%'
      OR a.skip_reason ILIKE '%' || trim(p_search) || '%'
    )
  ORDER BY a.created_at DESC
  LIMIT greatest(p_limit, 1)
  OFFSET greatest(p_offset, 0);
END;
$$;
