-- Fix partner route push: re-send on already-sent routes, notify bil-eier (routes_owner_only),
-- and log when no push devices are registered.

CREATE OR REPLACE FUNCTION public.trg_partner_route_sms_on_sent()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.dispatch_status = 'sent'
     AND (
       TG_OP = 'INSERT'
       OR coalesce(OLD.dispatch_status, '') IS DISTINCT FROM 'sent'
       OR coalesce(OLD.notify_channels, ARRAY[]::text[]) IS DISTINCT FROM coalesce(NEW.notify_channels, ARRAY[]::text[])
     ) THEN
    PERFORM public.notify_partner_route_assigned_sms(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_partner_route_sms_on_sent ON public.partner_route_shares;
CREATE TRIGGER trg_partner_route_sms_on_sent
  AFTER INSERT OR UPDATE OF dispatch_status, notify_channels ON public.partner_route_shares
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_partner_route_sms_on_sent();

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
  owner_only BOOLEAN;
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

  IF r IS NULL
     OR coalesce(r.partner_is_active, false) = false
     OR coalesce(r.dispatch_status, 'sent') <> 'sent'
     OR r.partner_vehicle_id IS NULL THEN
    RETURN 0;
  END IF;

  IF NOT public.partner_route_wants_channel(r.notify_channels, 'app')
     OR NOT public.company_partner_push_enabled(r.company_id, 'partner_route') THEN
    RETURN 0;
  END IF;

  owner_only := coalesce(r.routes_owner_only, true);

  SELECT name INTO shift_name FROM public.fleet_shift_definitions WHERE id = r.shift_id;

  driver_title := 'Ny rute i DriftPro';
  driver_body := 'Ny rute på ' || coalesce(r.unit_code, 'bil') ||
    CASE WHEN r.vehicle_reg IS NOT NULL AND trim(r.vehicle_reg) <> '' THEN ' (' || trim(r.vehicle_reg) || ')' ELSE '' END ||
    CASE WHEN shift_name IS NOT NULL THEN ' · ' || shift_name ELSE '' END ||
    '. Åpne appen for PDF og godkjenning.';

  -- Bil-eier / admin (samme mønster som SMS til eier)
  FOR d IN
    SELECT DISTINCT ppa.profile_id
    FROM public.partner_portal_accounts ppa
    JOIN public.profiles pr ON pr.id = ppa.profile_id AND coalesce(pr.is_active, true) = true
    WHERE ppa.partner_id = r.partner_id
      AND ppa.is_active = true
      AND ppa.profile_id IS NOT NULL
      AND coalesce(ppa.account_kind, 'owner') IN ('owner', 'admin')
      AND ppa.partner_vehicle_id IS NULL
  LOOP
    n := n + public.queue_push_to_profile_if_allowed(
      r.company_id,
      d.profile_id,
      driver_title,
      driver_body,
      'partner_route',
      'partner_route_shares',
      p_route_share_id,
      'partner_route',
      'Ny rute → bil-eier (push)',
      true,
      jsonb_build_object('type', 'partner_route', 'route_share_id', p_route_share_id::text)
    );
  END LOOP;

  -- Sjåfør på bilen når ruter deles direkte til sjåfør
  IF NOT owner_only THEN
    FOR d IN
      SELECT DISTINCT ppa.profile_id
      FROM public.partner_portal_accounts ppa
      JOIN public.profiles pr ON pr.id = ppa.profile_id AND coalesce(pr.is_active, true) = true
      WHERE ppa.partner_vehicle_id = r.partner_vehicle_id
        AND ppa.is_active = true
        AND coalesce(ppa.account_kind, 'driver') = 'driver'
        AND ppa.profile_id IS NOT NULL
    LOOP
      n := n + public.queue_push_to_profile_if_allowed(
        r.company_id,
        d.profile_id,
        driver_title,
        driver_body,
        'partner_route',
        'partner_route_shares',
        p_route_share_id,
        'partner_route',
        'Ny rute → sjåfør (push)',
        true,
        jsonb_build_object('type', 'partner_route', 'route_share_id', p_route_share_id::text)
      );
    END LOOP;
  END IF;

  IF n = 0 THEN
    PERFORM public.log_notification_audit(
      r.company_id, 'push', 'partner_route', 'partner_route',
      NULL, NULL, 'skipped', 'no_push_devices',
      'Ingen aktiv push-enhet for partner — logg inn i appen og slå på varsler',
      NULL, NULL, NULL,
      'partner_route_shares', p_route_share_id
    );
  END IF;

  RETURN n;
END;
$$;

COMMENT ON FUNCTION public.notify_partner_route_driver_push IS
  'Push ved rute-utsendelse til bil-eier (og sjåfør når routes_owner_only=false).';

-- Oppdater leveringsstatus: sjekk token på eier OG sjåfør
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
      prs.partner_vehicle_id,
      prs.partner_id
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
        FROM public.partner_portal_accounts ppa
        JOIN public.profiles pr ON pr.id = ppa.profile_id
        WHERE ppa.is_active = true
          AND ppa.profile_id IS NOT NULL
          AND coalesce(trim(pr.fcm_token), '') <> ''
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
