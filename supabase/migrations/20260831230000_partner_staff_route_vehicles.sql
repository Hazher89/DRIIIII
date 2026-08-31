-- Bil-spesifikk rutetilgang for ansatte (én eller flere MAVI-biler per ansatt).

CREATE TABLE IF NOT EXISTS public.partner_staff_route_vehicles (
  staff_id UUID NOT NULL REFERENCES public.partner_staff(id) ON DELETE CASCADE,
  partner_vehicle_id UUID NOT NULL REFERENCES public.partner_vehicles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (staff_id, partner_vehicle_id)
);

CREATE INDEX IF NOT EXISTS idx_partner_staff_route_vehicles_vehicle
  ON public.partner_staff_route_vehicles (partner_vehicle_id);

COMMENT ON TABLE public.partner_staff_route_vehicles IS
  'Hvilke partner-biler en ansatt kan se, akseptere ruter for og motta push på.';

ALTER TABLE public.partner_staff_route_vehicles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS partner_staff_route_vehicles_select ON public.partner_staff_route_vehicles;
CREATE POLICY partner_staff_route_vehicles_select ON public.partner_staff_route_vehicles
  FOR SELECT TO authenticated
  USING (
    staff_id IN (
      SELECT id FROM public.partner_staff WHERE profile_id = auth.uid()
    )
    OR staff_id IN (
      SELECT s.id
      FROM public.partner_staff s
      WHERE s.partner_id IN (
        SELECT partner_id FROM public.partner_portal_accounts
        WHERE profile_id = auth.uid() AND is_active AND account_kind = 'owner'
      )
    )
    OR staff_id IN (
      SELECT s.id
      FROM public.partner_staff s
      WHERE s.company_id IN (
        SELECT company_id FROM public.profiles
        WHERE id = auth.uid() AND company_id IS NOT NULL
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.profiles x
        WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
      )
    )
  );

GRANT SELECT ON public.partner_staff_route_vehicles TO authenticated;

CREATE OR REPLACE FUNCTION public.partner_staff_can_access_route_vehicle(
  p_profile_id UUID,
  p_partner_id UUID,
  p_partner_vehicle_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.partner_staff s
    JOIN public.partner_staff_route_vehicles srv ON srv.staff_id = s.id
    WHERE s.profile_id = p_profile_id
      AND s.partner_id = p_partner_id
      AND s.is_active = true
      AND s.can_manage_routes = true
      AND srv.partner_vehicle_id = p_partner_vehicle_id
  );
$$;

-- Erstatt bred partner-tilgang med bil-spesifikk tilgang for ansatte.
DROP POLICY IF EXISTS "partner_route_shares_select" ON public.partner_route_shares;
CREATE POLICY "partner_route_shares_select" ON public.partner_route_shares FOR SELECT USING (
  (
    company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
  )
  OR partner_id IN (
    SELECT ppa.partner_id FROM public.partner_portal_accounts ppa
    WHERE ppa.profile_id = auth.uid()
      AND ppa.is_active = true
      AND ppa.account_kind = 'owner'
  )
  OR public.partner_staff_can_access_route_vehicle(auth.uid(), partner_id, partner_vehicle_id)
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
    AND partner_vehicle_id IN (
      SELECT p.partner_vehicle_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
  )
);

DROP POLICY IF EXISTS "partner_route_shares_update" ON public.partner_route_shares;
CREATE POLICY "partner_route_shares_update" ON public.partner_route_shares FOR UPDATE USING (
  (
    company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
  )
  OR partner_id IN (
    SELECT ppa.partner_id FROM public.partner_portal_accounts ppa
    WHERE ppa.profile_id = auth.uid()
      AND ppa.is_active = true
      AND ppa.account_kind = 'owner'
  )
  OR public.partner_staff_can_access_route_vehicle(auth.uid(), partner_id, partner_vehicle_id)
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
    AND partner_vehicle_id IN (
      SELECT p.partner_vehicle_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
  )
);

CREATE OR REPLACE FUNCTION public.partner_staff_set_route_access(
  p_staff_id UUID,
  p_enabled BOOLEAN,
  p_vehicle_ids UUID[] DEFAULT NULL
)
RETURNS public.partner_staff
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.partner_staff%ROWTYPE;
  v_vid UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_staff FROM public.partner_staff WHERE id = p_staff_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ansatt ikke funnet';
  END IF;

  IF NOT public.partner_staff_can_manage(v_staff.partner_id, v_staff.company_id) THEN
    RAISE EXCEPTION 'Mangler tilgang';
  END IF;

  IF NOT coalesce(p_enabled, false) THEN
    UPDATE public.partner_staff
    SET can_manage_routes = false, updated_at = now()
    WHERE id = p_staff_id;
    DELETE FROM public.partner_staff_route_vehicles WHERE staff_id = p_staff_id;
    SELECT * INTO v_staff FROM public.partner_staff WHERE id = p_staff_id;
    RETURN v_staff;
  END IF;

  UPDATE public.partner_staff
  SET can_manage_routes = true, updated_at = now()
  WHERE id = p_staff_id;

  DELETE FROM public.partner_staff_route_vehicles WHERE staff_id = p_staff_id;

  IF p_vehicle_ids IS NOT NULL THEN
    FOREACH v_vid IN ARRAY p_vehicle_ids
    LOOP
      IF v_vid IS NULL THEN
        CONTINUE;
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM public.partner_vehicles pv
        WHERE pv.id = v_vid
          AND pv.partner_id = v_staff.partner_id
          AND pv.is_active = true
      ) THEN
        RAISE EXCEPTION 'Ugyldig bil for denne bedriften';
      END IF;
      INSERT INTO public.partner_staff_route_vehicles (staff_id, partner_vehicle_id)
      VALUES (p_staff_id, v_vid)
      ON CONFLICT DO NOTHING;
    END LOOP;
  END IF;

  SELECT * INTO v_staff FROM public.partner_staff WHERE id = p_staff_id;
  RETURN v_staff;
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_staff_set_route_vehicles(
  p_staff_id UUID,
  p_vehicle_ids UUID[] DEFAULT ARRAY[]::UUID[]
)
RETURNS public.partner_staff
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.partner_staff_set_route_access(
    p_staff_id,
    true,
    coalesce(p_vehicle_ids, ARRAY[]::UUID[])
  );
END;
$$;

-- Behold gammel RPC — deaktivering uten bil-liste.
CREATE OR REPLACE FUNCTION public.partner_staff_set_can_manage_routes(
  p_staff_id UUID,
  p_enabled BOOLEAN
)
RETURNS public.partner_staff
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.partner_staff_set_route_access(
    p_staff_id,
    coalesce(p_enabled, false),
    CASE WHEN coalesce(p_enabled, false) THEN NULL ELSE ARRAY[]::UUID[] END
  );
END;
$$;

-- Eksisterende ansatte med rutetilgang: alle aktive biler (bakoverkompatibilitet).
INSERT INTO public.partner_staff_route_vehicles (staff_id, partner_vehicle_id)
SELECT s.id, pv.id
FROM public.partner_staff s
JOIN public.partner_vehicles pv
  ON pv.partner_id = s.partner_id AND pv.is_active = true
WHERE s.can_manage_routes = true
ON CONFLICT DO NOTHING;

-- Push kun til ansatt når ruten gjelder tildelt bil.
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
      r.company_id, d.profile_id, driver_title, driver_body,
      'partner_route', 'partner_route_shares', p_route_share_id,
      'partner_route', 'Ny rute → bil-eier (push)', true,
      jsonb_build_object('type', 'partner_route', 'route_share_id', p_route_share_id::text)
    );
  END LOOP;

  FOR d IN
    SELECT DISTINCT s.profile_id
    FROM public.partner_staff s
    JOIN public.partner_staff_route_vehicles srv ON srv.staff_id = s.id
    JOIN public.profiles pr ON pr.id = s.profile_id AND coalesce(pr.is_active, true) = true
    WHERE s.partner_id = r.partner_id
      AND s.is_active = true
      AND s.can_manage_routes = true
      AND s.profile_id IS NOT NULL
      AND srv.partner_vehicle_id = r.partner_vehicle_id
  LOOP
    n := n + public.queue_push_to_profile_if_allowed(
      r.company_id, d.profile_id, driver_title, driver_body,
      'partner_route', 'partner_route_shares', p_route_share_id,
      'partner_route', 'Ny rute → ansatt (push)', true,
      jsonb_build_object('type', 'partner_route', 'route_share_id', p_route_share_id::text)
    );
  END LOOP;

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
        r.company_id, d.profile_id, driver_title, driver_body,
        'partner_route', 'partner_route_shares', p_route_share_id,
        'partner_route', 'Ny rute → sjåfør (push)', true,
        jsonb_build_object('type', 'partner_route', 'route_share_id', p_route_share_id::text)
      );
    END LOOP;
  END IF;

  IF n = 0 THEN
    PERFORM public.log_notification_audit(
      r.company_id, 'push', 'partner_route', 'partner_route',
      NULL, NULL, 'skipped', 'no_push_devices',
      'Ingen aktiv push-enhet — logg inn i appen og slå på varsler',
      NULL, NULL, NULL,
      'partner_route_shares', p_route_share_id
    );
  END IF;

  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_partner_route_pdf_opened(p_route_share_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  r public.partner_route_shares%ROWTYPE;
  first_open BOOLEAN := false;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  SELECT * INTO r FROM public.partner_route_shares WHERE id = p_route_share_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  IF NOT (
    EXISTS (
      SELECT 1 FROM public.profiles me
      WHERE me.id = uid
        AND me.company_id = r.company_id
        AND me.is_active = true
    )
    OR EXISTS (
      SELECT 1 FROM public.partner_portal_accounts ppa
      WHERE ppa.profile_id = uid
        AND ppa.is_active = true
        AND ppa.partner_id = r.partner_id
        AND (
          ppa.partner_vehicle_id IS NULL
          OR ppa.partner_vehicle_id = r.partner_vehicle_id
        )
    )
    OR public.partner_staff_can_access_route_vehicle(uid, r.partner_id, r.partner_vehicle_id)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'forbidden');
  END IF;

  IF r.pdf_opened_at IS NULL THEN
    first_open := true;
    UPDATE public.partner_route_shares
    SET
      pdf_opened_at = now(),
      pdf_opened_by = uid,
      pdf_open_count = greatest(coalesce(pdf_open_count, 0), 0) + 1
    WHERE id = p_route_share_id;
  ELSE
    UPDATE public.partner_route_shares
    SET pdf_open_count = coalesce(pdf_open_count, 0) + 1
    WHERE id = p_route_share_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'first_open', first_open,
    'pdf_opened_at', (SELECT pdf_opened_at FROM public.partner_route_shares WHERE id = p_route_share_id),
    'pdf_open_count', (SELECT pdf_open_count FROM public.partner_route_shares WHERE id = p_route_share_id)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.partner_staff_set_route_access(UUID, BOOLEAN, UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.partner_staff_set_route_vehicles(UUID, UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.partner_staff_can_access_route_vehicle(UUID, UUID, UUID) TO authenticated;
