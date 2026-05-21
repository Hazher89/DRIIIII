-- Partner-modul: SMS-logg kun for samarbeid/ruter/portal (ikke HMS/fravær/avvik).
-- Kjør etter sms_log_advanced_filters.sql

CREATE OR REPLACE FUNCTION public.is_partner_scope_sms(
  p_category TEXT,
  p_reference_type TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    COALESCE(p_category, '') LIKE 'partner%'
    OR COALESCE(p_reference_type, '') IN (
      'partners',
      'partner',
      'partner_route_shares',
      'partner_portal_accounts'
    );
$$;

CREATE OR REPLACE FUNCTION public.user_can_view_partner_sms_log()
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

  IF COALESCE((v_settings ->> 'partners')::boolean, false) THEN
    RETURN true;
  END IF;
  IF COALESCE((v_settings ->> 'samarbeidspartnere')::boolean, false) THEN
    RETURN true;
  END IF;
  IF COALESCE((v_settings ->> 'partners_admin')::boolean, false) THEN
    RETURN true;
  END IF;
  IF COALESCE((v_settings ->> 'fleet_ruter')::boolean, false) THEN
    RETURN true;
  END IF;

  RETURN COALESCE((v_settings ->> 'partners_tab_oversikt')::boolean, false)
    OR COALESCE((v_settings ->> 'partners_tab_bilkontroll')::boolean, false)
    OR COALESCE((v_settings ->> 'partners_tab_ruter')::boolean, false)
    OR COALESCE((v_settings ->> 'partners_tab_dokumenter')::boolean, false)
    OR COALESCE((v_settings ->> 'partners_tab_loyver')::boolean, false)
    OR COALESCE((v_settings ->> 'partners_tab_oppfolging')::boolean, false)
    OR COALESCE((v_settings ->> 'partners_tab_oppsummering')::boolean, false)
    OR COALESCE((v_settings ->> 'partners_tab_fri')::boolean, false);
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_partner_scope_sms(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_can_view_partner_sms_log() TO authenticated;

CREATE OR REPLACE FUNCTION public.list_partner_sms_log(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0,
  p_search TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_from_date TIMESTAMPTZ DEFAULT NULL,
  p_to_date TIMESTAMPTZ DEFAULT NULL,
  p_recipient TEXT DEFAULT NULL,
  p_sender TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT NULL,
  p_partner_id UUID DEFAULT NULL,
  p_sort TEXT DEFAULT 'created_desc'
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
  sender_name TEXT,
  partner_name TEXT,
  context_label TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
BEGIN
  IF NOT public.user_can_view_partner_sms_log() THEN
    RAISE EXCEPTION 'Ingen tilgang til partner SMS-logg';
  END IF;

  SELECT company_id INTO v_company_id
  FROM public.profiles
  WHERE id = auth.uid();

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
    COALESCE(
      o.to_user_id,
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
    'Mavi'::text AS sender_name,
    COALESCE(
      p_route.name,
      p_ref.name,
      p_meet.name
    ) AS partner_name,
    CASE
      WHEN o.reference_type = 'partner_route_shares' AND prs.id IS NOT NULL THEN
        'Rute ' || COALESCE(pv.unit_code, prs.title, left(prs.id::text, 8))
      WHEN o.category = 'partner_meeting' THEN 'Møte / oppfølging'
      WHEN o.category = 'partner_portal' THEN 'Portal-innlogging'
      WHEN o.category = 'partner_compose' THEN 'Manuell utsendelse'
      WHEN o.category = 'partner_route' THEN 'Rute varsling (sjåfør)'
      WHEN o.category = 'partner_route_owner' THEN 'Rute varsling (bil-eier)'
      ELSE COALESCE(o.category, 'Samarbeid')
    END AS context_label
  FROM public.sms_outbox o
  LEFT JOIN public.profiles pr ON pr.id = o.to_user_id
  LEFT JOIN public.profiles pt ON pt.id = o.triggered_by_user_id
  LEFT JOIN public.partner_route_shares prs
    ON o.reference_type = 'partner_route_shares' AND o.reference_id = prs.id
  LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
  LEFT JOIN public.partners p_route ON p_route.id = prs.partner_id
  LEFT JOIN public.partners p_ref
    ON o.reference_type IN ('partner', 'partners') AND o.reference_id = p_ref.id
  LEFT JOIN public.partners p_meet
    ON o.reference_type = 'partner' AND o.reference_id = p_meet.id
  WHERE o.company_id = v_company_id
    AND public.is_partner_scope_sms(o.category, o.reference_type)
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
      OR COALESCE(p_route.name, p_ref.name, p_meet.name, '') ILIKE '%' || trim(p_search) || '%'
      OR COALESCE(pv.unit_code, '') ILIKE '%' || trim(p_search) || '%'
    )
    AND (
      p_partner_id IS NULL
      OR prs.partner_id = p_partner_id
      OR p_ref.id = p_partner_id
      OR p_meet.id = p_partner_id
    )
  ORDER BY
    CASE WHEN p_sort = 'created_asc' THEN o.created_at END ASC,
    CASE WHEN p_sort = 'sent_desc' THEN o.sent_at END DESC NULLS LAST,
    CASE WHEN p_sort = 'sent_asc' THEN o.sent_at END ASC NULLS LAST,
    CASE WHEN p_sort = 'recipient_asc' THEN COALESCE(pr.full_name, o.to_phone) END ASC,
    CASE WHEN p_sort = 'recipient_desc' THEN COALESCE(pr.full_name, o.to_phone) END DESC,
    o.created_at DESC
  LIMIT greatest(p_limit, 1)
  OFFSET greatest(p_offset, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.count_partner_sms_log(
  p_search TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_from_date TIMESTAMPTZ DEFAULT NULL,
  p_to_date TIMESTAMPTZ DEFAULT NULL,
  p_recipient TEXT DEFAULT NULL,
  p_sender TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT NULL,
  p_partner_id UUID DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  c BIGINT;
BEGIN
  IF NOT public.user_can_view_partner_sms_log() THEN
    RETURN 0;
  END IF;

  SELECT company_id INTO v_company_id
  FROM public.profiles
  WHERE id = auth.uid();

  SELECT count(*)::bigint INTO c
  FROM public.sms_outbox o
  LEFT JOIN public.profiles pr ON pr.id = o.to_user_id
  LEFT JOIN public.profiles pt ON pt.id = o.triggered_by_user_id
  LEFT JOIN public.partner_route_shares prs
    ON o.reference_type = 'partner_route_shares' AND o.reference_id = prs.id
  LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
  LEFT JOIN public.partners p_ref
    ON o.reference_type IN ('partner', 'partners') AND o.reference_id = p_ref.id
  LEFT JOIN public.partners p_meet
    ON o.reference_type = 'partner' AND o.reference_id = p_meet.id
  LEFT JOIN public.partners p_route ON p_route.id = prs.partner_id
  WHERE o.company_id = v_company_id
    AND public.is_partner_scope_sms(o.category, o.reference_type)
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
      OR COALESCE(p_route.name, p_ref.name, p_meet.name, '') ILIKE '%' || trim(p_search) || '%'
      OR COALESCE(pv.unit_code, '') ILIKE '%' || trim(p_search) || '%'
    )
    AND (
      p_partner_id IS NULL
      OR prs.partner_id = p_partner_id
      OR p_ref.id = p_partner_id
      OR p_meet.id = p_partner_id
    );

  RETURN c;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_partner_sms_log(
  INT, INT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT, UUID, TEXT
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.count_partner_sms_log(
  TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT, UUID
) TO authenticated;

CREATE INDEX IF NOT EXISTS idx_sms_outbox_partner_category
  ON public.sms_outbox(company_id, created_at DESC)
  WHERE category LIKE 'partner%';
