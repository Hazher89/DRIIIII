-- Leiebil-sporing (drive monitor): egen funksjon, ikke ruter/Auto Mass.
-- Enhetskontoer merkes med profiles.drive_monitor_device.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS drive_monitor_device BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.profiles.drive_monitor_device IS
  'Når true: innlogging åpner låst leiebil-sporing (kiosk), ikke vanlig DriftPro.';

CREATE TABLE IF NOT EXISTS public.drive_monitor_settings (
  company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  exit_pin_hash TEXT,
  hard_brake_ms2 NUMERIC NOT NULL DEFAULT 3.5,
  hard_accel_ms2 NUMERIC NOT NULL DEFAULT 3.0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.drive_monitor_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  device_profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  partner_vehicle_id UUID REFERENCES public.partner_vehicles(id) ON DELETE SET NULL,
  vehicle_label TEXT,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'ended')),
  score NUMERIC,
  km NUMERIC NOT NULL DEFAULT 0,
  event_count INT NOT NULL DEFAULT 0,
  rough_event_count INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_drive_monitor_sessions_company
  ON public.drive_monitor_sessions(company_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_drive_monitor_sessions_device
  ON public.drive_monitor_sessions(device_profile_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_drive_monitor_sessions_active
  ON public.drive_monitor_sessions(company_id, status)
  WHERE status = 'active';

CREATE TABLE IF NOT EXISTS public.drive_monitor_samples (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES public.drive_monitor_sessions(id) ON DELETE CASCADE,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  speed_kmh NUMERIC,
  heading_deg NUMERIC,
  accel_ms2 NUMERIC
);

CREATE INDEX IF NOT EXISTS idx_drive_monitor_samples_session
  ON public.drive_monitor_samples(session_id, recorded_at DESC);

CREATE TABLE IF NOT EXISTS public.drive_monitor_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES public.drive_monitor_sessions(id) ON DELETE CASCADE,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  event_type TEXT NOT NULL
    CHECK (event_type IN ('hard_brake', 'hard_accel', 'sharp_turn', 'speeding', 'idle', 'ok_period')),
  severity TEXT NOT NULL DEFAULT 'info'
    CHECK (severity IN ('info', 'warning', 'rough')),
  speed_kmh NUMERIC,
  accel_ms2 NUMERIC,
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  note TEXT
);

CREATE INDEX IF NOT EXISTS idx_drive_monitor_events_session
  ON public.drive_monitor_events(session_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_drive_monitor_events_company
  ON public.drive_monitor_events(company_id, recorded_at DESC);

ALTER TABLE public.drive_monitor_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drive_monitor_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drive_monitor_samples ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drive_monitor_events ENABLE ROW LEVEL SECURITY;

-- Device accounts: read/write own company rows when drive_monitor_device.
-- Admins/superadmin: full company read.

CREATE OR REPLACE FUNCTION public.can_view_drive_monitor(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.company_id = p_company_id
      AND (
        p.role IN ('superadmin', 'admin')
        OR coalesce((p.access_settings ->> 'drive_monitor')::boolean, false)
        OR coalesce(p.drive_monitor_device, false)
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_drive_monitor(p_company_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.company_id = p_company_id
      AND (
        p.role IN ('superadmin', 'admin')
        OR coalesce((p.access_settings ->> 'drive_monitor')::boolean, false)
      )
  );
$$;

DROP POLICY IF EXISTS drive_monitor_settings_select ON public.drive_monitor_settings;
CREATE POLICY drive_monitor_settings_select ON public.drive_monitor_settings
  FOR SELECT TO authenticated
  USING (public.can_view_drive_monitor(company_id));

DROP POLICY IF EXISTS drive_monitor_settings_upsert ON public.drive_monitor_settings;
CREATE POLICY drive_monitor_settings_upsert ON public.drive_monitor_settings
  FOR ALL TO authenticated
  USING (public.can_manage_drive_monitor(company_id))
  WITH CHECK (public.can_manage_drive_monitor(company_id));

DROP POLICY IF EXISTS drive_monitor_sessions_select ON public.drive_monitor_sessions;
CREATE POLICY drive_monitor_sessions_select ON public.drive_monitor_sessions
  FOR SELECT TO authenticated
  USING (public.can_view_drive_monitor(company_id));

DROP POLICY IF EXISTS drive_monitor_sessions_insert ON public.drive_monitor_sessions;
CREATE POLICY drive_monitor_sessions_insert ON public.drive_monitor_sessions
  FOR INSERT TO authenticated
  WITH CHECK (
    public.can_view_drive_monitor(company_id)
    AND device_profile_id = auth.uid()
  );

DROP POLICY IF EXISTS drive_monitor_sessions_update ON public.drive_monitor_sessions;
CREATE POLICY drive_monitor_sessions_update ON public.drive_monitor_sessions
  FOR UPDATE TO authenticated
  USING (
    public.can_view_drive_monitor(company_id)
    AND (device_profile_id = auth.uid() OR public.can_manage_drive_monitor(company_id))
  );

DROP POLICY IF EXISTS drive_monitor_samples_select ON public.drive_monitor_samples;
CREATE POLICY drive_monitor_samples_select ON public.drive_monitor_samples
  FOR SELECT TO authenticated
  USING (public.can_view_drive_monitor(company_id));

DROP POLICY IF EXISTS drive_monitor_samples_insert ON public.drive_monitor_samples;
CREATE POLICY drive_monitor_samples_insert ON public.drive_monitor_samples
  FOR INSERT TO authenticated
  WITH CHECK (
    public.can_view_drive_monitor(company_id)
    AND EXISTS (
      SELECT 1 FROM public.drive_monitor_sessions s
      WHERE s.id = session_id AND s.device_profile_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS drive_monitor_events_select ON public.drive_monitor_events;
CREATE POLICY drive_monitor_events_select ON public.drive_monitor_events
  FOR SELECT TO authenticated
  USING (public.can_view_drive_monitor(company_id));

DROP POLICY IF EXISTS drive_monitor_events_insert ON public.drive_monitor_events;
CREATE POLICY drive_monitor_events_insert ON public.drive_monitor_events
  FOR INSERT TO authenticated
  WITH CHECK (
    public.can_view_drive_monitor(company_id)
    AND EXISTS (
      SELECT 1 FROM public.drive_monitor_sessions s
      WHERE s.id = session_id AND s.device_profile_id = auth.uid()
    )
  );

-- Merk ansatt 010101 som enhetskonto hvis profilen finnes (passord settes utenfor SQL).
UPDATE public.profiles
SET drive_monitor_device = true
WHERE trim(coalesce(employee_number, '')) = '010101';

GRANT EXECUTE ON FUNCTION public.can_view_drive_monitor(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_manage_drive_monitor(UUID) TO authenticated, service_role;
