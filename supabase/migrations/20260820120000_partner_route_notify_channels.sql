-- Per-rute varselkanaler (app / sms / email) + leveringsstatus-RPC.
-- Push til alle aktive portal-sjåfører på bilen (Android/iOS via FCM).

ALTER TABLE public.partner_route_shares
  ADD COLUMN IF NOT EXISTS notify_channels TEXT[] NOT NULL DEFAULT ARRAY['app','sms','email']::text[];

COMMENT ON COLUMN public.partner_route_shares.notify_channels IS
  'Kanaler ved publish med varsel: app, sms, email. Tom/ignoreres når dispatch_status != sent.';

CREATE OR REPLACE FUNCTION public.partner_route_wants_channel(
  p_channels TEXT[],
  p_channel TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(p_channel = ANY (COALESCE(p_channels, ARRAY['app','sms','email']::text[])), true);
$$;

-- Push til alle aktive portal-sjåfører på bilen (respekterer notify_channels).
CREATE OR REPLACE FUNCTION public.notify_partner_route_driver_push(p_route_share_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  shift_name TEXT;
  driver_title TEXT;
  driver_body TEXT;
  d RECORD;
  n INT := 0;
BEGIN
  SELECT
    prs.*,
    pv.unit_code,
    pv.registration_number AS vehicle_reg,
    p.name AS partner_name,
    p.is_active AS partner_is_active
  INTO r
  FROM public.partner_route_shares prs
  LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
  LEFT JOIN public.partners p ON p.id = prs.partner_id
  WHERE prs.id = p_route_share_id;

  IF r IS NULL
     OR coalesce(r.partner_is_active, false) = false
     OR coalesce(r.dispatch_status, 'sent') <> 'sent'
     OR r.partner_vehicle_id IS NULL THEN
    RETURN 0;
  END IF;

  IF NOT public.partner_route_wants_channel(r.notify_channels, 'app') THEN
    RETURN 0;
  END IF;

  SELECT name INTO shift_name FROM public.fleet_shift_definitions WHERE id = r.shift_id;

  driver_title := 'Ny rute i DriftPro';
  driver_body := 'Ny rute på ' || coalesce(r.unit_code, 'bil') ||
    CASE WHEN r.vehicle_reg IS NOT NULL AND trim(r.vehicle_reg) <> '' THEN ' (' || trim(r.vehicle_reg) || ')' ELSE '' END ||
    CASE WHEN shift_name IS NOT NULL THEN ' · ' || shift_name ELSE '' END ||
    '. Åpne appen for PDF og godkjenning.';

  FOR d IN
    SELECT DISTINCT ON (upd.fcm_token)
      ppa.profile_id,
      upd.fcm_token
    FROM public.partner_portal_accounts ppa
    JOIN public.user_push_devices upd
      ON upd.profile_id = ppa.profile_id
     AND upd.is_active = true
    JOIN public.profiles pr ON pr.id = ppa.profile_id AND pr.is_active = true
    WHERE ppa.partner_vehicle_id = r.partner_vehicle_id
      AND ppa.is_active = true
      AND coalesce(ppa.account_kind, 'driver') = 'driver'
      AND ppa.profile_id IS NOT NULL
    ORDER BY upd.fcm_token, upd.last_seen_at DESC
  LOOP
    IF public.queue_partner_route_push(
      r.company_id,
      d.profile_id,
      d.fcm_token,
      driver_title,
      driver_body,
      p_route_share_id
    ) IS NOT NULL THEN
      n := n + 1;
    END IF;
  END LOOP;

  -- Fallback: eldre enkelt-token på profiles.fcm_token
  FOR d IN
    SELECT DISTINCT ppa.profile_id, pr.fcm_token
    FROM public.partner_portal_accounts ppa
    JOIN public.profiles pr ON pr.id = ppa.profile_id
    WHERE ppa.partner_vehicle_id = r.partner_vehicle_id
      AND ppa.is_active = true
      AND coalesce(ppa.account_kind, 'driver') = 'driver'
      AND ppa.profile_id IS NOT NULL
      AND pr.is_active = true
      AND coalesce(trim(pr.fcm_token), '') <> ''
      AND NOT EXISTS (
        SELECT 1 FROM public.user_push_devices upd
        WHERE upd.profile_id = ppa.profile_id
          AND upd.fcm_token = pr.fcm_token
          AND upd.is_active = true
      )
  LOOP
    IF public.queue_partner_route_push(
      r.company_id,
      d.profile_id,
      d.fcm_token,
      driver_title,
      driver_body,
      p_route_share_id
    ) IS NOT NULL THEN
      n := n + 1;
    END IF;
  END LOOP;

  RETURN n;
END;
$$;

-- SMS/e-post/push ved sent — respekter notify_channels.
CREATE OR REPLACE FUNCTION public.notify_partner_route_assigned_sms(p_route_share_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  shift_name TEXT;
  driver_msg TEXT;
  owner_msg TEXT;
  email_sub TEXT;
  email_body TEXT;
  n INT := 0;
  driver_phone TEXT;
  owner_only BOOLEAN;
  sent_phones TEXT[] := ARRAY[]::TEXT[];
  v_skip_email BOOLEAN := false;
  want_sms BOOLEAN;
  want_email BOOLEAN;
  want_app BOOLEAN;
BEGIN
  SELECT
    prs.*,
    pv.unit_code,
    pv.registration_number AS vehicle_reg,
    p.name AS partner_name,
    p.is_active AS partner_is_active,
    coalesce(p.routes_owner_only, true) AS routes_owner_only
  INTO r
  FROM public.partner_route_shares prs
  LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
  LEFT JOIN public.partners p ON p.id = prs.partner_id
  WHERE prs.id = p_route_share_id;

  IF r IS NULL OR coalesce(r.partner_is_active, false) = false THEN
    RETURN 0;
  END IF;
  IF r.partner_vehicle_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.partner_vehicles pv2
    WHERE pv2.id = r.partner_vehicle_id AND pv2.is_active = true
  ) THEN
    RETURN 0;
  END IF;
  IF coalesce(r.dispatch_status, 'sent') <> 'sent' THEN
    RETURN 0;
  END IF;

  want_sms := public.partner_route_wants_channel(r.notify_channels, 'sms');
  want_email := public.partner_route_wants_channel(r.notify_channels, 'email');
  want_app := public.partner_route_wants_channel(r.notify_channels, 'app');

  IF NOT want_sms AND NOT want_email AND NOT want_app THEN
    RETURN 0;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.email_outbox e
    WHERE e.reference_type = 'partner_route_shares'
      AND e.reference_id = p_route_share_id
      AND e.category = 'partner_route_share'
      AND e.created_at > now() - interval '10 minutes'
  ) INTO v_skip_email;

  owner_only := coalesce(r.routes_owner_only, true);
  SELECT name INTO shift_name FROM public.fleet_shift_definitions WHERE id = r.shift_id;

  driver_msg := 'Ny rute tildelt ' || coalesce(r.unit_code, '') ||
    CASE WHEN r.vehicle_reg IS NOT NULL AND trim(r.vehicle_reg) <> '' THEN ' (' || trim(r.vehicle_reg) || ')' ELSE '' END ||
    CASE WHEN shift_name IS NOT NULL THEN ' · Skift: ' || shift_name ELSE '' END ||
    '. Logg inn i DriftPro for PDF og godkjenning.';

  owner_msg := 'Ny rute på ' || coalesce(r.unit_code, 'bil') ||
    ' — ' || coalesce(r.partner_name, 'din bedrift') ||
    CASE WHEN shift_name IS NOT NULL THEN ' · ' || shift_name ELSE '' END ||
    '. Logg inn i DriftPro for oversikt og godkjenning.';

  SELECT e.subject, e.body_html
  INTO email_sub, email_body
  FROM public.build_partner_route_published_email(
    r.unit_code,
    r.vehicle_reg,
    r.partner_name,
    shift_name,
    r.title,
    r.share_date,
    r.route_start_at
  ) e;

  IF want_sms THEN
    IF NOT owner_only THEN
      SELECT public.normalize_phone_no(ppa.phone) INTO driver_phone
      FROM public.partner_portal_accounts ppa
      JOIN public.partners p ON p.id = ppa.partner_id AND p.is_active = true
      WHERE ppa.partner_vehicle_id = r.partner_vehicle_id
        AND ppa.is_active = true
        AND coalesce(ppa.account_kind, 'driver') = 'driver'
        AND ppa.phone IS NOT NULL
      ORDER BY ppa.updated_at DESC NULLS LAST
      LIMIT 1;

      IF driver_phone IS NOT NULL AND NOT (driver_phone = ANY (sent_phones)) THEN
        IF public.queue_partner_sms_if_allowed(
          r.company_id, driver_phone, driver_msg, 'partner_route', 'partner_route',
          'partner_route_shares', r.id, 'Ny rute → sjåfør'
        ) IS NOT NULL THEN
          sent_phones := array_append(sent_phones, driver_phone);
          n := n + 1;
        END IF;
      END IF;
    END IF;

    n := n + public.notify_partner_owner_phones(
      r.company_id, r.partner_id, owner_msg, 'partner_route_owner', 'partner_route_owner',
      'partner_route_shares', r.id, 'Ny rute → bil-eier'
    );
  END IF;

  IF want_email AND NOT v_skip_email THEN
    n := n + public.notify_partner_owner_emails(
      r.company_id, r.partner_id, email_sub, email_body, 'partner_route_share',
      'partner_route_owner', 'partner_route_shares', r.id, 'Ny rute (e-post HTML)'
    );
  END IF;

  IF want_app THEN
    n := n + public.notify_partner_route_driver_push(p_route_share_id);
  END IF;

  RETURN n;
END;
$$;

COMMENT ON FUNCTION public.notify_partner_route_assigned_sms IS
  'Køer SMS/e-post/push for rute ved dispatch_status=sent, styrt av notify_channels.';

-- Leveringsstatus per rute (app / sms / e-post) + om sjåfør har app-token.
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
  needs_attention BOOLEAN
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
      prs.partner_vehicle_id
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
        WHERE ppa.partner_vehicle_id = s.partner_vehicle_id
          AND ppa.is_active = true
          AND coalesce(ppa.account_kind, 'driver') = 'driver'
          AND ppa.profile_id IS NOT NULL
      ) OR EXISTS (
        SELECT 1
        FROM public.partner_portal_accounts ppa
        JOIN public.profiles pr ON pr.id = ppa.profile_id
        WHERE ppa.partner_vehicle_id = s.partner_vehicle_id
          AND ppa.is_active = true
          AND coalesce(ppa.account_kind, 'driver') = 'driver'
          AND coalesce(trim(pr.fcm_token), '') <> ''
      ) AS has_token,
      EXISTS (
        SELECT 1
        FROM public.partner_portal_accounts ppa
        WHERE ppa.partner_vehicle_id = s.partner_vehicle_id
          AND ppa.is_active = true
          AND coalesce(ppa.account_kind, 'driver') = 'driver'
          AND coalesce(trim(ppa.phone), '') <> ''
      ) AS has_phone
    FROM shares s
  )
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
    ) AS needs_attention
  FROM shares s
  LEFT JOIN sms ON sms.rid = s.id
  LEFT JOIN email ON email.rid = s.id
  LEFT JOIN push ON push.rid = s.id
  LEFT JOIN driver_caps dc ON dc.rid = s.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_partner_route_notify_delivery(UUID, UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.notify_partner_route_driver_push(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.notify_partner_route_assigned_sms(UUID) TO authenticated, service_role;
