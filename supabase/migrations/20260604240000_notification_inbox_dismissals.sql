-- Varselbjelle: leveringsstatus (sendt/kø/feil), merket som lest, tømme.

CREATE TABLE IF NOT EXISTS public.notification_inbox_dismissals (
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  dismiss_key TEXT NOT NULL,
  dismissed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, dismiss_key)
);

CREATE INDEX IF NOT EXISTS idx_notification_inbox_dismissals_user
  ON public.notification_inbox_dismissals(user_id, dismissed_at DESC);

ALTER TABLE public.notification_inbox_dismissals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notification_inbox_dismissals_own ON public.notification_inbox_dismissals;
CREATE POLICY notification_inbox_dismissals_own ON public.notification_inbox_dismissals
  FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

GRANT SELECT, INSERT, DELETE ON public.notification_inbox_dismissals TO authenticated;

CREATE OR REPLACE FUNCTION public.dismiss_notification_inbox(p_keys TEXT[])
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n INT := 0;
  k TEXT;
BEGIN
  IF p_keys IS NULL OR array_length(p_keys, 1) IS NULL THEN
    RETURN 0;
  END IF;
  FOREACH k IN ARRAY p_keys LOOP
    IF k IS NULL OR length(trim(k)) = 0 THEN
      CONTINUE;
    END IF;
    INSERT INTO public.notification_inbox_dismissals(user_id, dismiss_key)
    VALUES (auth.uid(), trim(k))
    ON CONFLICT (user_id, dismiss_key) DO UPDATE SET dismissed_at = now();
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.dismiss_all_notification_inbox()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_role TEXT;
  keys TEXT[];
BEGIN
  SELECT company_id, role::text INTO v_company_id, v_role
  FROM public.profiles WHERE id = auth.uid();

  IF v_company_id IS NULL THEN
    RETURN 0;
  END IF;

  SELECT coalesce(array_agg(a.id::text), ARRAY[]::TEXT[])
  INTO keys
  FROM public.notification_audit a
  WHERE a.company_id = v_company_id
    AND a.created_at > now() - interval '30 days'
    AND NOT EXISTS (
      SELECT 1 FROM public.notification_inbox_dismissals d
      WHERE d.user_id = auth.uid() AND d.dismiss_key = a.id::text
    );

  IF v_role = 'superadmin' THEN
    keys := keys || coalesce((
      SELECT array_agg('sms_fail_' || o.id::text)
      FROM public.sms_outbox o
      WHERE o.company_id = v_company_id
        AND o.sent_at IS NULL
        AND o.error_message IS NOT NULL
        AND o.created_at > now() - interval '30 days'
        AND NOT EXISTS (
          SELECT 1 FROM public.notification_inbox_dismissals d
          WHERE d.user_id = auth.uid() AND d.dismiss_key = 'sms_fail_' || o.id::text
        )
    ), ARRAY[]::TEXT[]);
  END IF;

  RETURN public.dismiss_notification_inbox(keys);
END;
$$;

GRANT EXECUTE ON FUNCTION public.dismiss_notification_inbox(TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dismiss_all_notification_inbox() TO authenticated;

DROP FUNCTION IF EXISTS public.list_notification_audit(INT, INT, TEXT, TEXT, TEXT, BOOLEAN, TIMESTAMPTZ, TIMESTAMPTZ, TEXT);

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
      WHEN a.event_channel = 'sms' AND s.id IS NOT NULL AND s.error_message IS NOT NULL AND s.sent_at IS NULL THEN 'failed'
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
          ELSE coalesce(a.category, 'Varsel')
        END
      ),
      200
    ) AS message_preview
  FROM public.notification_audit a
  LEFT JOIN public.partners p ON p.id = a.partner_id
  LEFT JOIN public.sms_outbox s ON s.id = a.sms_outbox_id
  LEFT JOIN public.email_outbox e ON e.id = a.email_outbox_id
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
