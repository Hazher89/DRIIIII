-- Kun bil-eier: alle ruter, varsler og aksept — sjåfør får ingenting.

ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS routes_owner_only BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.partners.routes_owner_only IS
  'true = kun bil-eier får SMS, ser og aksepterer alle ruter for bedriften; sjåfør-portal uten ruter';

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
BEGIN
  SELECT
    prs.*,
    pv.phone AS vehicle_phone,
    pv.unit_code,
    pv.registration_number AS vehicle_reg,
    p.phone AS partner_phone,
    p.name AS partner_name,
    coalesce(p.routes_owner_only, false) AS routes_owner_only,
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

  owner_only := coalesce(r.routes_owner_only, false);

  SELECT name INTO shift_name FROM public.fleet_shift_definitions WHERE id = r.shift_id;

  driver_msg := 'Ny rute tildelt ' || coalesce(r.unit_code, '') ||
    CASE WHEN r.vehicle_reg IS NOT NULL AND trim(r.vehicle_reg) <> '' THEN ' (' || trim(r.vehicle_reg) || ')' ELSE '' END ||
    CASE WHEN shift_name IS NOT NULL THEN ' · Skift: ' || shift_name ELSE '' END ||
    CASE WHEN r.route_start_at IS NOT NULL THEN
      ' · Start ' || to_char(r.route_start_at AT TIME ZONE 'Europe/Oslo', 'DD.MM HH24:MI')
    ELSE '' END ||
    '. Logg inn i DriftPro for PDF og aksept.';

  IF owner_only THEN
    owner_msg := 'Ny rute på ' || coalesce(r.unit_code, 'bil') ||
      CASE WHEN r.vehicle_reg IS NOT NULL AND trim(r.vehicle_reg) <> '' THEN ' (' || trim(r.vehicle_reg) || ')' ELSE '' END ||
      ' — ' || coalesce(r.partner_name, 'din bedrift') ||
      CASE WHEN shift_name IS NOT NULL THEN ' · ' || shift_name ELSE '' END ||
      CASE WHEN r.route_start_at IS NOT NULL THEN
        ' · Start ' || to_char(r.route_start_at AT TIME ZONE 'Europe/Oslo', 'DD.MM HH24:MI')
      ELSE '' END ||
      '. Du er bil-eier: se alle ruter, notater og godkjenn i DriftPro.';
  ELSE
    owner_msg := 'Ny rute på ' || coalesce(r.unit_code, 'bil') ||
      CASE WHEN r.vehicle_reg IS NOT NULL AND trim(r.vehicle_reg) <> '' THEN ' (' || trim(r.vehicle_reg) || ')' ELSE '' END ||
      ' — ' || coalesce(r.partner_name, 'din bedrift') ||
      CASE WHEN shift_name IS NOT NULL THEN ' · ' || shift_name ELSE '' END ||
      CASE WHEN r.route_start_at IS NOT NULL THEN
        ' · Start ' || to_char(r.route_start_at AT TIME ZONE 'Europe/Oslo', 'DD.MM HH24:MI')
      ELSE '' END ||
      '. Logg inn som bil-eier i DriftPro for oversikt og godkjenning.';
  END IF;

  IF NOT owner_only THEN
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
  END IF;

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

-- Sjåfør: ingen tilgang til ruter når routes_owner_only
DROP POLICY IF EXISTS "partner_route_shares_select" ON public.partner_route_shares;
CREATE POLICY "partner_route_shares_select" ON public.partner_route_shares FOR SELECT USING (
  (
    company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_id IS NOT NULL AND p.partner_vehicle_id IS NULL
    )
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
    AND partner_vehicle_id IN (
      SELECT p.partner_vehicle_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.partners pt
      WHERE pt.id = partner_route_shares.partner_id
        AND coalesce(pt.routes_owner_only, false) = true
    )
  )
);

DROP POLICY IF EXISTS "partner_route_shares_update" ON public.partner_route_shares;
CREATE POLICY "partner_route_shares_update" ON public.partner_route_shares FOR UPDATE USING (
  (
    company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_id IS NOT NULL AND p.partner_vehicle_id IS NULL
    )
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
    AND partner_vehicle_id IN (
      SELECT p.partner_vehicle_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.partners pt
      WHERE pt.id = partner_route_shares.partner_id
        AND coalesce(pt.routes_owner_only, false) = true
    )
  )
);
