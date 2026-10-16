-- Utvid leveringsstatus med PDF-sti og feilsammendrag for utsendingsrapport.

DROP FUNCTION IF EXISTS public.get_partner_route_notify_delivery(UUID, UUID[]);

CREATE OR REPLACE FUNCTION public.get_partner_route_notify_delivery(
  p_company_id UUID,
  p_share_ids UUID[] DEFAULT NULL
)
RETURNS TABLE (
  share_id UUID,
  dispatch_status TEXT,
  notify_channels TEXT[],
  wants_app BOOLEAN,
  wants_sms BOOLEAN,
  wants_email BOOLEAN,
  sms_queued BOOLEAN,
  sms_sent BOOLEAN,
  sms_failed BOOLEAN,
  email_queued BOOLEAN,
  email_sent BOOLEAN,
  email_failed BOOLEAN,
  push_queued BOOLEAN,
  push_sent BOOLEAN,
  push_failed BOOLEAN,
  driver_has_app_token BOOLEAN,
  driver_has_phone BOOLEAN,
  needs_attention BOOLEAN,
  pdf_storage_path TEXT,
  storage_ok BOOLEAN,
  error_summary TEXT,
  partner_vehicle_id UUID,
  share_date DATE,
  title TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH shares AS (
    SELECT
      prs.id,
      prs.dispatch_status,
      coalesce(prs.notify_channels, ARRAY['app','sms','email']::text[]) AS channels,
      prs.partner_vehicle_id,
      prs.partner_id,
      prs.pdf_storage_path,
      prs.share_date,
      prs.title
    FROM public.partner_route_shares prs
    WHERE prs.company_id = p_company_id
      AND (p_share_ids IS NULL OR prs.id = ANY (p_share_ids))
  ),
  sms AS (
    SELECT
      o.reference_id AS rid,
      bool_or(o.sent_at IS NULL AND coalesce(o.attempts, 0) < 5 AND o.error_message IS NULL) AS queued,
      bool_or(o.sent_at IS NOT NULL) AS sent,
      bool_or(o.error_message IS NOT NULL AND o.sent_at IS NULL) AS failed
    FROM public.sms_outbox o
    WHERE o.reference_type = 'partner_route_shares'
      AND o.reference_id IN (SELECT id FROM shares)
    GROUP BY o.reference_id
  ),
  email AS (
    SELECT
      o.reference_id AS rid,
      bool_or(o.sent_at IS NULL AND coalesce(o.attempts, 0) < 5 AND o.error_message IS NULL) AS queued,
      bool_or(o.sent_at IS NOT NULL) AS sent,
      bool_or(o.error_message IS NOT NULL AND o.sent_at IS NULL) AS failed
    FROM public.email_outbox o
    WHERE o.reference_type = 'partner_route_shares'
      AND o.reference_id IN (SELECT id FROM shares)
    GROUP BY o.reference_id
  ),
  push AS (
    SELECT
      o.reference_id AS rid,
      bool_or(o.sent_at IS NULL AND coalesce(o.attempts, 0) < 5 AND o.error_message IS NULL) AS queued,
      bool_or(o.sent_at IS NOT NULL) AS sent,
      bool_or(o.error_message IS NOT NULL AND o.sent_at IS NULL) AS failed
    FROM public.push_outbox o
    WHERE o.reference_type = 'partner_route_shares'
      AND o.reference_id IN (SELECT id FROM shares)
    GROUP BY o.reference_id
  ),
  driver_caps AS (
    SELECT
      s.id AS rid,
      EXISTS (
        SELECT 1
        FROM public.partner_portal_accounts ppa
        JOIN public.user_push_devices upd
          ON upd.profile_id = ppa.profile_id AND upd.is_active = true
        WHERE ppa.is_active = true
          AND ppa.profile_id IS NOT NULL
          AND (
            (
              ppa.partner_id = s.partner_id
              AND coalesce(ppa.account_kind, 'owner') IN ('owner', 'admin')
              AND ppa.partner_vehicle_id IS NULL
            )
            OR (
              ppa.partner_vehicle_id = s.partner_vehicle_id
              AND coalesce(ppa.account_kind, 'driver') = 'driver'
            )
          )
      ) OR EXISTS (
        SELECT 1
        FROM public.partner_staff st
        JOIN public.user_push_devices upd
          ON upd.profile_id = st.profile_id AND upd.is_active = true
        WHERE st.partner_id = s.partner_id
          AND st.is_active = true
          AND st.can_manage_routes = true
          AND st.profile_id IS NOT NULL
      ) OR EXISTS (
        SELECT 1
        FROM public.partner_portal_accounts ppa
        JOIN public.profiles pr ON pr.id = ppa.profile_id
        WHERE ppa.is_active = true
          AND ppa.profile_id IS NOT NULL
          AND nullif(trim(pr.fcm_token), '') IS NOT NULL
          AND (
            (
              ppa.partner_id = s.partner_id
              AND coalesce(ppa.account_kind, 'owner') IN ('owner', 'admin')
              AND ppa.partner_vehicle_id IS NULL
            )
            OR (
              ppa.partner_vehicle_id = s.partner_vehicle_id
              AND coalesce(ppa.account_kind, 'driver') = 'driver'
            )
          )
      ) OR EXISTS (
        SELECT 1
        FROM public.partner_staff st
        JOIN public.profiles pr ON pr.id = st.profile_id
        WHERE st.partner_id = s.partner_id
          AND st.is_active = true
          AND st.can_manage_routes = true
          AND st.profile_id IS NOT NULL
          AND nullif(trim(pr.fcm_token), '') IS NOT NULL
      ) AS has_token,
      EXISTS (
        SELECT 1
        FROM public.partner_portal_accounts ppa
        WHERE ppa.is_active = true
          AND ppa.profile_id IS NOT NULL
          AND coalesce(trim(ppa.phone), '') <> ''
          AND (
            (
              ppa.partner_id = s.partner_id
              AND coalesce(ppa.account_kind, 'owner') IN ('owner', 'admin')
              AND ppa.partner_vehicle_id IS NULL
            )
            OR (
              ppa.partner_vehicle_id = s.partner_vehicle_id
              AND coalesce(ppa.account_kind, 'driver') = 'driver'
            )
          )
      ) OR EXISTS (
        SELECT 1
        FROM public.partner_staff st
        WHERE st.partner_id = s.partner_id
          AND st.is_active = true
          AND st.can_manage_routes = true
          AND coalesce(trim(st.phone), '') <> ''
      ) AS has_phone
    FROM shares s
  ),
  scored AS (
    SELECT
      s.id AS share_id,
      s.dispatch_status,
      s.channels AS notify_channels,
      public.partner_route_wants_channel(s.channels, 'app') AS wants_app,
      public.partner_route_wants_channel(s.channels, 'sms') AS wants_sms,
      public.partner_route_wants_channel(s.channels, 'email') AS wants_email,
      coalesce(sms.queued, false) AS sms_queued,
      coalesce(sms.sent, false) AS sms_sent,
      coalesce(sms.failed, false) AS sms_failed,
      coalesce(email.queued, false) AS email_queued,
      coalesce(email.sent, false) AS email_sent,
      coalesce(email.failed, false) AS email_failed,
      coalesce(push.queued, false) AS push_queued,
      coalesce(push.sent, false) AS push_sent,
      coalesce(push.failed, false) AS push_failed,
      coalesce(dc.has_token, false) AS driver_has_app_token,
      coalesce(dc.has_phone, false) AS driver_has_phone,
      (
        s.dispatch_status = 'registered'
        OR (
          s.dispatch_status = 'sent'
          AND (
            (public.partner_route_wants_channel(s.channels, 'sms')
              AND NOT coalesce(sms.sent, false)
              AND NOT coalesce(sms.queued, false))
            OR (public.partner_route_wants_channel(s.channels, 'email')
              AND NOT coalesce(email.sent, false)
              AND NOT coalesce(email.queued, false))
            OR (public.partner_route_wants_channel(s.channels, 'app')
              AND NOT coalesce(push.sent, false)
              AND NOT coalesce(push.queued, false)
              AND NOT coalesce(dc.has_token, false))
            OR coalesce(sms.failed, false)
            OR coalesce(email.failed, false)
            OR coalesce(push.failed, false)
          )
        )
      ) AS needs_attention,
      nullif(trim(s.pdf_storage_path), '') AS pdf_storage_path,
      (nullif(trim(s.pdf_storage_path), '') IS NOT NULL) AS storage_ok,
      s.partner_vehicle_id,
      s.share_date,
      s.title
    FROM shares s
    LEFT JOIN sms ON sms.rid = s.id
    LEFT JOIN email ON email.rid = s.id
    LEFT JOIN push ON push.rid = s.id
    LEFT JOIN driver_caps dc ON dc.rid = s.id
  )
  SELECT
    sc.share_id,
    sc.dispatch_status,
    sc.notify_channels,
    sc.wants_app,
    sc.wants_sms,
    sc.wants_email,
    sc.sms_queued,
    sc.sms_sent,
    sc.sms_failed,
    sc.email_queued,
    sc.email_sent,
    sc.email_failed,
    sc.push_queued,
    sc.push_sent,
    sc.push_failed,
    sc.driver_has_app_token,
    sc.driver_has_phone,
    sc.needs_attention,
    sc.pdf_storage_path,
    sc.storage_ok,
    nullif(
      trim(both ' · ' FROM concat_ws(
        ' · ',
        CASE WHEN sc.pdf_storage_path IS NULL THEN 'PDF mangler sti' END,
        CASE
          WHEN sc.wants_sms AND sc.sms_failed THEN 'SMS feilet'
          WHEN sc.wants_sms AND NOT sc.sms_sent AND NOT sc.sms_queued AND NOT sc.driver_has_phone
            THEN 'Mangler telefon'
          WHEN sc.wants_sms AND NOT sc.sms_sent AND NOT sc.sms_queued
            THEN 'SMS ikke køet'
          ELSE NULL
        END,
        CASE
          WHEN sc.wants_app AND sc.push_failed THEN 'Push feilet'
          WHEN sc.wants_app AND NOT sc.push_sent AND NOT sc.push_queued AND NOT sc.driver_has_app_token
            THEN 'Mangler app'
          WHEN sc.wants_app AND NOT sc.push_sent AND NOT sc.push_queued
            THEN 'Push ikke køet'
          ELSE NULL
        END,
        CASE
          WHEN sc.wants_email AND sc.email_failed THEN 'E-post feilet'
          WHEN sc.wants_email AND NOT sc.email_sent AND NOT sc.email_queued
            THEN 'E-post ikke køet'
          ELSE NULL
        END,
        CASE WHEN sc.dispatch_status = 'registered' THEN 'Registrert uten varsel' END
      )),
      ''
    ) AS error_summary,
    sc.partner_vehicle_id,
    sc.share_date,
    sc.title
  FROM scored sc;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_partner_route_notify_delivery(UUID, UUID[]) TO authenticated;

COMMENT ON FUNCTION public.get_partner_route_notify_delivery(UUID, UUID[]) IS
  'Leveringsstatus App/SMS/e-post + PDF-sti/feilsammendrag per rute.';
