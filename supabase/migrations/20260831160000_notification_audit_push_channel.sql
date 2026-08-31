-- Tillat 'push' i notification_audit (tri-kanal varsler).

ALTER TABLE public.notification_audit
  DROP CONSTRAINT IF EXISTS notification_audit_event_channel_check;

ALTER TABLE public.notification_audit
  ADD CONSTRAINT notification_audit_event_channel_check
  CHECK (event_channel IN ('sms', 'email', 'push'));

-- Vis riktig status for push-rader i audit-listen
CREATE OR REPLACE FUNCTION public.list_notification_audit(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0,
  p_channel TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_partner_scope BOOLEAN DEFAULT NULL,
  p_from_date TIMESTAMPTZ DEFAULT NULL,
  p_to_date TIMESTAMPTZ DEFAULT NULL,
  p_search TEXT DEFAULT NULL,
  p_exclude_dismissed BOOLEAN DEFAULT false
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
  partner_name TEXT,
  delivery_status TEXT,
  is_dismissed BOOLEAN,
  message_preview TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_company_id UUID;
  v_role TEXT;
  v_uid UUID := auth.uid();
BEGIN
  SELECT company_id, role::text INTO v_company_id, v_role
  FROM public.profiles WHERE id = v_uid;

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
    p.name AS partner_name,
    CASE
      WHEN a.status = 'skipped' THEN 'skipped'
      WHEN a.event_channel = 'sms' AND s.id IS NOT NULL AND s.sent_at IS NOT NULL THEN 'sent'
      WHEN a.event_channel = 'email' AND e.id IS NOT NULL AND e.sent_at IS NOT NULL THEN 'sent'
      WHEN a.event_channel = 'push' AND po.id IS NOT NULL AND po.sent_at IS NOT NULL THEN 'sent'
      WHEN a.event_channel = 'sms' AND s.id IS NOT NULL AND s.error_message IS NOT NULL AND s.sent_at IS NULL THEN 'failed'
      WHEN a.event_channel = 'email' AND e.id IS NOT NULL AND e.error_message IS NOT NULL AND e.sent_at IS NULL THEN 'failed'
      WHEN a.event_channel = 'push' AND po.id IS NOT NULL AND po.error_message IS NOT NULL AND po.sent_at IS NULL THEN 'failed'
      WHEN a.status = 'queued' THEN 'queued'
      ELSE 'queued'
    END AS delivery_status,
    EXISTS (
      SELECT 1 FROM public.notification_inbox_dismissals d
      WHERE d.user_id = v_uid AND d.dismiss_key = a.id::text
    ) AS is_dismissed,
    left(
      coalesce(
        nullif(trim(a.description), ''),
        CASE a.setting_key
          WHEN 'partner_portal' THEN 'Portal-innlogging'
          WHEN 'partner_route' THEN 'Rute tildelt'
          WHEN 'partner_route_owner' THEN 'Rute til bedriftsansvarlig'
          WHEN 'partner_meeting' THEN 'Møte / audit'
          WHEN 'partner_document' THEN 'Dokument delt'
          WHEN 'partner_deduction' THEN 'Bot / trekk'
          ELSE coalesce(a.category, 'Varsel')
        END
      ),
      200
    ) AS message_preview
  FROM public.notification_audit a
  LEFT JOIN public.partners p ON p.id = a.partner_id
  LEFT JOIN public.sms_outbox s ON s.id = a.sms_outbox_id
  LEFT JOIN public.email_outbox e ON e.id = a.email_outbox_id
  LEFT JOIN LATERAL (
    SELECT po2.id, po2.sent_at, po2.error_message
    FROM public.push_outbox po2
    WHERE a.event_channel = 'push'
      AND po2.reference_type = a.reference_type
      AND po2.reference_id = a.reference_id
      AND po2.fcm_token = a.recipient
      AND po2.created_at >= a.created_at - interval '1 minute'
    ORDER BY po2.created_at ASC
    LIMIT 1
  ) po ON true
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
    AND (
      NOT p_exclude_dismissed
      OR NOT EXISTS (
        SELECT 1 FROM public.notification_inbox_dismissals d
        WHERE d.user_id = v_uid AND d.dismiss_key = a.id::text
      )
    )
  ORDER BY a.created_at DESC
  LIMIT greatest(p_limit, 1)
  OFFSET greatest(p_offset, 0);
END;
$$;
