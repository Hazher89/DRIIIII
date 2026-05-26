-- Last-mile logistics core (DriftPro Ruteplan)
-- Erstatter operativ dataflyt fra SAP + TransFleet; master flåte forblir i DriftPro.

-- ── Ordre (inngang — erstatter SAP ordrelinjer / PDF-parsing over tid) ──
CREATE TABLE IF NOT EXISTS public.lm_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  source TEXT NOT NULL DEFAULT 'manual'
    CHECK (source IN ('manual', 'api', 'pdf_import', 'sap_legacy', 'edi')),
  external_ref TEXT,
  customer_name TEXT NOT NULL,
  customer_phone TEXT,
  address_line TEXT NOT NULL,
  postal_code TEXT,
  city TEXT,
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  time_window_start TIMESTAMPTZ,
  time_window_end TIMESTAMPTZ,
  weight_kg NUMERIC(10,2),
  volume_m3 NUMERIC(10,3),
  service_notes TEXT,
  requires_installation BOOLEAN NOT NULL DEFAULT false,
  requires_carry_belt BOOLEAN NOT NULL DEFAULT false,
  requires_old_appliance_pickup BOOLEAN NOT NULL DEFAULT false,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'planned', 'assigned', 'in_transit', 'delivered', 'failed', 'cancelled')),
  sap_inbox_id UUID REFERENCES public.sap_route_inbox(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_lm_orders_company_status
  ON public.lm_orders (company_id, status, created_at DESC);

-- ── Ruter (planlagt leveranse — erstatter TransFleet-ruter) ──
CREATE TABLE IF NOT EXISTS public.lm_routes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  route_date DATE NOT NULL,
  partner_vehicle_id UUID NOT NULL REFERENCES public.partner_vehicles(id) ON DELETE RESTRICT,
  partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE RESTRICT,
  shift_id UUID REFERENCES public.fleet_shift_definitions(id) ON DELETE SET NULL,
  driver_profile_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'optimizing', 'ready', 'published', 'in_progress', 'completed', 'cancelled')),
  total_weight_kg NUMERIC(10,2),
  total_volume_m3 NUMERIC(10,3),
  payload_limit_kg NUMERIC(10,2),
  payload_limit_m3 NUMERIC(10,3),
  optimization_run_id UUID,
  published_at TIMESTAMPTZ,
  partner_route_share_id UUID REFERENCES public.partner_route_shares(id) ON DELETE SET NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_lm_routes_company_date
  ON public.lm_routes (company_id, route_date DESC);

CREATE INDEX IF NOT EXISTS idx_lm_routes_vehicle_date
  ON public.lm_routes (partner_vehicle_id, route_date);

-- ── Stopp ──
CREATE TABLE IF NOT EXISTS public.lm_route_stops (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  route_id UUID NOT NULL REFERENCES public.lm_routes(id) ON DELETE CASCADE,
  lm_order_id UUID REFERENCES public.lm_orders(id) ON DELETE SET NULL,
  sequence INT NOT NULL,
  planned_arrival_at TIMESTAMPTZ,
  planned_departure_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'en_route', 'arrived', 'completed', 'skipped', 'failed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (route_id, sequence)
);

CREATE INDEX IF NOT EXISTS idx_lm_route_stops_route
  ON public.lm_route_stops (route_id, sequence);

-- ── Egendefinerte felt per rute ──
CREATE TABLE IF NOT EXISTS public.lm_route_custom_field_defs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  field_key TEXT NOT NULL,
  label TEXT NOT NULL,
  field_type TEXT NOT NULL DEFAULT 'text'
    CHECK (field_type IN ('text', 'bool', 'number', 'select')),
  options JSONB,
  sort_order INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, field_key)
);

CREATE TABLE IF NOT EXISTS public.lm_route_custom_field_values (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  route_id UUID NOT NULL REFERENCES public.lm_routes(id) ON DELETE CASCADE,
  field_def_id UUID NOT NULL REFERENCES public.lm_route_custom_field_defs(id) ON DELETE CASCADE,
  value_text TEXT,
  value_bool BOOLEAN,
  value_number NUMERIC(12,4),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (route_id, field_def_id)
);

-- ── VRPTW-kjøringer ──
CREATE TABLE IF NOT EXISTS public.lm_optimization_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  route_date DATE NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'running', 'completed', 'failed')),
  input_order_ids UUID[] NOT NULL DEFAULT '{}',
  result JSONB,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

ALTER TABLE public.lm_routes
  ADD CONSTRAINT lm_routes_optimization_fk
  FOREIGN KEY (optimization_run_id) REFERENCES public.lm_optimization_runs(id) ON DELETE SET NULL;

-- ── GPS (sjåfør-app → Realtime) ──
CREATE TABLE IF NOT EXISTS public.lm_gps_positions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  partner_vehicle_id UUID NOT NULL REFERENCES public.partner_vehicles(id) ON DELETE CASCADE,
  route_id UUID REFERENCES public.lm_routes(id) ON DELETE SET NULL,
  driver_profile_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  lat DOUBLE PRECISION NOT NULL,
  lng DOUBLE PRECISION NOT NULL,
  speed_kmh NUMERIC(6,2),
  heading_deg NUMERIC(5,2),
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_lm_gps_vehicle_time
  ON public.lm_gps_positions (partner_vehicle_id, recorded_at DESC);

-- ── Proof of Delivery ──
CREATE TABLE IF NOT EXISTS public.lm_pod_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  route_stop_id UUID NOT NULL REFERENCES public.lm_route_stops(id) ON DELETE CASCADE,
  signer_name TEXT,
  photo_storage_paths TEXT[] NOT NULL DEFAULT '{}',
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  delivered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  notes TEXT
);

-- ── Offentlig kundesporing ──
CREATE TABLE IF NOT EXISTS public.lm_tracking_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  route_id UUID NOT NULL REFERENCES public.lm_routes(id) ON DELETE CASCADE,
  public_token TEXT NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(16), 'hex'),
  expires_at TIMESTAMPTZ NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Lager / framplukk ──
CREATE TABLE IF NOT EXISTS public.lm_warehouse_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  barcode TEXT NOT NULL,
  serial_number TEXT,
  shelf_location TEXT,
  lm_order_id UUID REFERENCES public.lm_orders(id) ON DELETE SET NULL,
  state TEXT NOT NULL DEFAULT 'received'
    CHECK (state IN ('received', 'staged', 'loaded', 'delivered', 'returned')),
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  received_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  UNIQUE (company_id, barcode)
);

-- ── Sync-logg fra DriftPro master ──
CREATE TABLE IF NOT EXISTS public.lm_fleet_sync_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  vehicles_synced INT NOT NULL DEFAULT 0,
  drivers_synced INT NOT NULL DEFAULT 0,
  partners_synced INT NOT NULL DEFAULT 0,
  payload JSONB,
  synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── updated_at triggers ──
CREATE OR REPLACE FUNCTION public.lm_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS lm_orders_updated ON public.lm_orders;
CREATE TRIGGER lm_orders_updated BEFORE UPDATE ON public.lm_orders
  FOR EACH ROW EXECUTE FUNCTION public.lm_set_updated_at();

DROP TRIGGER IF EXISTS lm_routes_updated ON public.lm_routes;
CREATE TRIGGER lm_routes_updated BEFORE UPDATE ON public.lm_routes
  FOR EACH ROW EXECUTE FUNCTION public.lm_set_updated_at();

-- ── RLS ──
ALTER TABLE public.lm_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lm_routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lm_route_stops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lm_route_custom_field_defs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lm_route_custom_field_values ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lm_optimization_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lm_gps_positions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lm_pod_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lm_tracking_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lm_warehouse_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lm_fleet_sync_runs ENABLE ROW LEVEL SECURITY;

-- Company-scoped policies (internal dispatchers)
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'lm_orders', 'lm_routes', 'lm_route_stops', 'lm_route_custom_field_defs',
    'lm_route_custom_field_values', 'lm_optimization_runs', 'lm_gps_positions',
    'lm_pod_records', 'lm_tracking_sessions', 'lm_warehouse_items', 'lm_fleet_sync_runs'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I_select ON public.%I', t, t);
    EXECUTE format(
      'CREATE POLICY %I_select ON public.%I FOR SELECT USING (company_id = public.get_user_company_id())',
      t, t
    );
    EXECUTE format('DROP POLICY IF EXISTS %I_insert ON public.%I', t, t);
    EXECUTE format(
      'CREATE POLICY %I_insert ON public.%I FOR INSERT WITH CHECK (company_id = public.get_user_company_id())',
      t, t
    );
    EXECUTE format('DROP POLICY IF EXISTS %I_update ON public.%I', t, t);
    EXECUTE format(
      'CREATE POLICY %I_update ON public.%I FOR UPDATE USING (company_id = public.get_user_company_id())',
      t, t
    );
    EXECUTE format('DROP POLICY IF EXISTS %I_delete ON public.%I', t, t);
    EXECUTE format(
      'CREATE POLICY %I_delete ON public.%I FOR DELETE USING (company_id = public.get_user_company_id())',
      t, t
    );
  END LOOP;
END $$;

-- Sjåfør: les egen rute + skriv GPS/PoD (utvides i fase 3)
DROP POLICY IF EXISTS lm_routes_driver_select ON public.lm_routes;
CREATE POLICY lm_routes_driver_select ON public.lm_routes FOR SELECT USING (
  driver_profile_id = auth.uid()
  OR company_id = public.get_user_company_id()
);

COMMENT ON TABLE public.lm_orders IS 'Last-mile kundeordre — erstatter SAP ordreinngang over tid';
COMMENT ON TABLE public.lm_routes IS 'Planlagte ruter — erstatter TransFleet ruteplan';
COMMENT ON TABLE public.lm_gps_positions IS 'Live GPS fra sjåfør-app';
COMMENT ON TABLE public.lm_pod_records IS 'Proof of delivery';
