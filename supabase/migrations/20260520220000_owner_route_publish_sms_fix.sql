-- Bil-eier skal få SMS når rute publiseres (ikke bare ved portal-passord).
-- Utvidet telefon-oppslag + trigger ved dispatch_status = sent.

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
BEGIN
  SELECT
    prs.*,
    pv.phone AS vehicle_phone,
    pv.unit_code,
    pv.registration_number AS vehicle_reg,
    p.phone AS partner_phone,
    p.name AS partner_name,
    ppa_drv.phone AS driver_portal_phone
  INTO r
  FROM public.partner_route_shares prs
  LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
  LEFT JOIN public.partners p ON p.id = prs.partner_id
  LEFT JOIN public.partner_portal_accounts ppa_drv ON
    ppa_drv.partner_vehicle_id = pv.id
    AND ppa_drv.is_active = true
    AND coalesce(ppa_drv.account_kind, 'driver') = 'driver'
  WHERE prs.id = p_route_share_id;

  IF r IS NULL THEN
    RETURN 0;
  END IF;

  IF coalesce(r.dispatch_status, 'sent') <> 'sent' THEN
    RETURN 0;
  END IF;

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
    '. Logg inn som bil-eier i DriftPro for oversikt og godkjenning.';

  driver_phone := public.normalize_phone_no(coalesce(r.vehicle_phone, r.driver_portal_phone));
  IF driver_phone IS NOT NULL THEN
    PERFORM public.queue_sms(
      r.company_id,
      driver_phone,
      driver_msg,
      'partner_route',
      'partner_route_shares',
      r.id
    );
    n := n + 1;
  END IF;

  -- Bil-eier: alltid egen SMS (selv om samme nr som sjåfør — annet innhold).
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
        AND pr.phone IS NOT NULL
      UNION ALL
      SELECT pr.phone
      FROM public.profiles pr
      WHERE pr.partner_id = r.partner_id
        AND pr.partner_vehicle_id IS NULL
        AND pr.phone IS NOT NULL
    ) src
    WHERE public.normalize_phone_no(src.phone) IS NOT NULL
  LOOP
    owner_phone := owner_rec.phone;
    IF owner_phone IS NOT NULL THEN
      PERFORM public.queue_sms(
        r.company_id,
        owner_phone,
        owner_msg,
        'partner_route_owner',
        'partner_route_shares',
        r.id
      );
      n := n + 1;
    END IF;
  END LOOP;

  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_partner_route_assigned_sms(UUID) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.trg_partner_route_sms_on_sent()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.dispatch_status = 'sent'
     AND (TG_OP = 'INSERT' OR coalesce(OLD.dispatch_status, '') IS DISTINCT FROM 'sent') THEN
    PERFORM public.notify_partner_route_assigned_sms(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_partner_route_sms_on_sent ON public.partner_route_shares;
CREATE TRIGGER trg_partner_route_sms_on_sent
  AFTER INSERT OR UPDATE OF dispatch_status ON public.partner_route_shares
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_partner_route_sms_on_sent();
