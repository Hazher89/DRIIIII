-- Offentlig kundesporing (token) + standard egendefinerte felt

CREATE OR REPLACE FUNCTION public.lm_public_tracking(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  sess RECORD;
  r JSONB;
  gps JSONB;
  stops JSONB;
BEGIN
  SELECT * INTO sess FROM lm_tracking_sessions
  WHERE public_token = p_token AND is_active = true AND expires_at > NOW()
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_build_object(
    'unit_code', pv.unit_code,
    'driver_name', pv.driver_name,
    'status', lr.status,
    'route_date', lr.route_date
  ) INTO r
  FROM lm_routes lr
  JOIN partner_vehicles pv ON pv.id = lr.partner_vehicle_id
  WHERE lr.id = sess.route_id;

  SELECT jsonb_build_object('lat', lat, 'lng', lng, 'recorded_at', recorded_at) INTO gps
  FROM lm_gps_positions
  WHERE route_id = sess.route_id
  ORDER BY recorded_at DESC
  LIMIT 1;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'sequence', sequence,
    'status', status,
    'planned_arrival_at', planned_arrival_at
  ) ORDER BY sequence), '[]'::jsonb) INTO stops
  FROM lm_route_stops
  WHERE route_id = sess.route_id;

  RETURN jsonb_build_object('route', r, 'gps', gps, 'stops', stops);
END;
$$;

GRANT EXECUTE ON FUNCTION public.lm_public_tracking(TEXT) TO anon, authenticated;

-- Standard egendefinerte felt (Elkjøp)
INSERT INTO public.lm_route_custom_field_defs (company_id, field_key, label, field_type, sort_order)
SELECT c.id, v.field_key, v.label, v.field_type, v.sort_order
FROM public.companies c
CROSS JOIN (
  VALUES
    ('installation', 'Montering påkrevd', 'bool', 1),
    ('carry_belt', 'Bærebelte', 'bool', 2),
    ('old_appliance', 'Retur av gammelt produkt', 'bool', 3),
    ('floor_note', 'Etasje / portkode', 'text', 4)
) AS v(field_key, label, field_type, sort_order)
ON CONFLICT (company_id, field_key) DO NOTHING;

-- Realtime for GPS (ignorer hvis allerede lagt til)
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.lm_gps_positions;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END $$;
