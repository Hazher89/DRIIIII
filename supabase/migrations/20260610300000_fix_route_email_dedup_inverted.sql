-- Fiks: e-post ble ikke sendt ved rutevarsel fordi dedup-sjekken var snudd.
-- v_send_email ble TRUE når e-post allerede fantes → e-post hoppet over ved første utsendelse.

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

  IF NOT v_skip_email THEN
    n := n + public.notify_partner_owner_emails(
      r.company_id, r.partner_id, email_sub, email_body, 'partner_route_share',
      'partner_route_owner', 'partner_route_shares', r.id, 'Ny rute (e-post HTML)'
    );
  END IF;

  RETURN n;
END;
$$;

COMMENT ON FUNCTION public.notify_partner_route_assigned_sms IS
  'SMS + maks én HTML-e-post per rute (hopp over e-post hvis allerede køet siste 10 min).';
