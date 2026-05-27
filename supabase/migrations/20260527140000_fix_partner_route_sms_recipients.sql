-- Rute-SMS: respekter routes_owner_only, ikke send til fjernede/inaktive brukere, dedupliser telefon.

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
  n INT := 0;
  driver_phone TEXT;
  owner_phone TEXT;
  owner_rec RECORD;
  owner_only BOOLEAN;
  sent_phones TEXT[] := ARRAY[]::TEXT[];
BEGIN
  SELECT
    prs.*,
    pv.unit_code,
    pv.registration_number AS vehicle_reg,
    p.phone AS partner_phone,
    p.name AS partner_name,
    coalesce(p.routes_owner_only, true) AS routes_owner_only
  INTO r
  FROM public.partner_route_shares prs
  LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
  LEFT JOIN public.partners p ON p.id = prs.partner_id
  WHERE prs.id = p_route_share_id;

  IF r IS NULL THEN
    RETURN 0;
  END IF;

  IF coalesce(r.dispatch_status, 'sent') <> 'sent' THEN
    RETURN 0;
  END IF;

  owner_only := coalesce(r.routes_owner_only, true);

  SELECT name INTO shift_name FROM public.fleet_shift_definitions WHERE id = r.shift_id;

  driver_msg := 'Ny rute tildelt ' || coalesce(r.unit_code, '') ||
    CASE WHEN r.vehicle_reg IS NOT NULL AND trim(r.vehicle_reg) <> '' THEN ' (' || trim(r.vehicle_reg) || ')' ELSE '' END ||
    CASE WHEN shift_name IS NOT NULL THEN ' · Skift: ' || shift_name ELSE '' END ||
    CASE WHEN r.route_start_at IS NOT NULL THEN
      ' · Start ' || to_char(r.route_start_at AT TIME ZONE 'Europe/Oslo', 'DD.MM HH24:MI')
    ELSE '' END ||
    '. Logg inn i DriftPro for PDF og aksept.';

  owner_msg := 'Ny rute på ' || coalesce(r.unit_code, 'bil') ||
    CASE WHEN r.vehicle_reg IS NOT NULL AND trim(r.vehicle_reg) <> '' THEN ' (' || trim(r.vehicle_reg) || ')' ELSE '' END ||
    ' — ' || coalesce(r.partner_name, 'din bedrift') ||
    CASE WHEN shift_name IS NOT NULL THEN ' · ' || shift_name ELSE '' END ||
    CASE WHEN r.route_start_at IS NOT NULL THEN
      ' · Start ' || to_char(r.route_start_at AT TIME ZONE 'Europe/Oslo', 'DD.MM HH24:MI')
    ELSE '' END ||
    '. Logg inn i DriftPro for oversikt og godkjenning.';

  -- Sjåfør-SMS kun når bedriften har valgt at sjåfør også skal varsles.
  -- Bruker KUN aktiv sjåfør-portal (ikke vehicle.phone — den kan ligge igjen etter slettet bruker).
  IF NOT owner_only THEN
    SELECT public.normalize_phone_no(ppa.phone) INTO driver_phone
    FROM public.partner_portal_accounts ppa
    WHERE ppa.partner_vehicle_id = r.partner_vehicle_id
      AND ppa.is_active = true
      AND coalesce(ppa.account_kind, 'driver') = 'driver'
      AND ppa.phone IS NOT NULL
    ORDER BY ppa.updated_at DESC NULLS LAST, ppa.created_at DESC
    LIMIT 1;

    IF driver_phone IS NOT NULL AND NOT (driver_phone = ANY (sent_phones)) THEN
      PERFORM public.queue_sms(
        r.company_id,
        driver_phone,
        driver_msg,
        'partner_route',
        'partner_route_shares',
        r.id
      );
      sent_phones := array_append(sent_phones, driver_phone);
      n := n + 1;
    END IF;
  END IF;

  -- Bil-eiere: kun aktive kontoer/profiler uten kjøretøy-kobling (ikke sjåfør-profil).
  FOR owner_rec IN
    SELECT DISTINCT public.normalize_phone_no(src.phone) AS phone
    FROM (
      SELECT p.phone
      FROM public.partners p
      WHERE p.id = r.partner_id AND p.phone IS NOT NULL
      UNION ALL
      SELECT ppa.phone
      FROM public.partner_portal_accounts ppa
      WHERE ppa.partner_id = r.partner_id
        AND ppa.is_active = true
        AND coalesce(ppa.account_kind, case when ppa.partner_vehicle_id is null then 'owner' else 'driver' end) = 'owner'
        AND ppa.phone IS NOT NULL
      UNION ALL
      SELECT pr.phone
      FROM public.partner_portal_accounts ppa
      JOIN public.profiles pr ON pr.id = ppa.profile_id
      WHERE ppa.partner_id = r.partner_id
        AND ppa.is_active = true
        AND coalesce(ppa.account_kind, case when ppa.partner_vehicle_id is null then 'owner' else 'driver' end) = 'owner'
        AND pr.is_active = true
        AND pr.phone IS NOT NULL
      UNION ALL
      SELECT pr.phone
      FROM public.profiles pr
      WHERE pr.partner_id = r.partner_id
        AND pr.partner_vehicle_id IS NULL
        AND pr.is_active = true
        AND pr.phone IS NOT NULL
    ) src
    WHERE public.normalize_phone_no(src.phone) IS NOT NULL
  LOOP
    owner_phone := owner_rec.phone;
    IF owner_phone IS NOT NULL AND NOT (owner_phone = ANY (sent_phones)) THEN
      PERFORM public.queue_sms(
        r.company_id,
        owner_phone,
        owner_msg,
        'partner_route_owner',
        'partner_route_shares',
        r.id
      );
      sent_phones := array_append(sent_phones, owner_phone);
      n := n + 1;
    END IF;
  END LOOP;

  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_partner_route_assigned_sms(UUID) TO authenticated, service_role;
