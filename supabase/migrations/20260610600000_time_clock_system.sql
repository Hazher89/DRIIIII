-- Stempling / time clock system (Tidsbanken-style kiosk + admin timeliste)

-- ── Company kiosk settings ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.time_clock_settings (
  company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  kiosk_slug TEXT NOT NULL,
  kiosk_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  company_display_name TEXT,
  punch_reset_seconds INT NOT NULL DEFAULT 4,
  default_work_type_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT time_clock_settings_slug_format CHECK (kiosk_slug ~ '^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$')
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_time_clock_settings_slug
  ON public.time_clock_settings (lower(kiosk_slug));

-- ── Work types (arbeidstyper) ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.time_work_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'shift'
    CHECK (category IN ('shift', 'absence', 'holiday', 'other')),
  payroll_code TEXT,
  color_hex TEXT NOT NULL DEFAULT '#0D9488',
  is_default_punch BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, code)
);

CREATE INDEX IF NOT EXISTS idx_time_work_types_company
  ON public.time_work_types (company_id, sort_order);

-- ── Employee PIN for kiosk ────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.time_clock_pins (
  profile_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  employee_number TEXT NOT NULL,
  pin_hash TEXT NOT NULL,
  failed_attempts INT NOT NULL DEFAULT 0,
  locked_until TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, employee_number)
);

CREATE INDEX IF NOT EXISTS idx_time_clock_pins_company
  ON public.time_clock_pins (company_id);

-- ── Mobile / web punch access flag on profiles ────────────────────────────────

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS time_clock_mobile_allowed BOOLEAN NOT NULL DEFAULT FALSE;

-- ── Current clock state per employee ──────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.time_clock_state (
  profile_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  is_clocked_in BOOLEAN NOT NULL DEFAULT FALSE,
  work_type_id UUID REFERENCES public.time_work_types(id) ON DELETE SET NULL,
  clocked_in_at TIMESTAMPTZ,
  last_punch_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_time_clock_state_company
  ON public.time_clock_state (company_id, is_clocked_in);

-- ── Punch event log ───────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.time_punch_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  punch_type TEXT NOT NULL CHECK (punch_type IN ('in', 'out')),
  work_type_id UUID REFERENCES public.time_work_types(id) ON DELETE SET NULL,
  punched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  source TEXT NOT NULL DEFAULT 'kiosk'
    CHECK (source IN ('kiosk', 'mobile', 'web', 'manual')),
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_time_punch_events_profile_day
  ON public.time_punch_events (profile_id, punched_at DESC);

-- ── Timesheet entries (manual + derived) ──────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.time_timesheet_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  work_date DATE NOT NULL,
  work_type_id UUID NOT NULL REFERENCES public.time_work_types(id) ON DELETE RESTRICT,
  start_time TIME,
  end_time TIME,
  hours NUMERIC(6, 2) NOT NULL DEFAULT 0,
  department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
  project TEXT,
  activity TEXT,
  invoice_note TEXT,
  note TEXT,
  is_locked BOOLEAN NOT NULL DEFAULT FALSE,
  is_approved BOOLEAN NOT NULL DEFAULT FALSE,
  source TEXT NOT NULL DEFAULT 'manual'
    CHECK (source IN ('punch', 'manual')),
  punch_event_in_id UUID REFERENCES public.time_punch_events(id) ON DELETE SET NULL,
  punch_event_out_id UUID REFERENCES public.time_punch_events(id) ON DELETE SET NULL,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_time_timesheet_profile_week
  ON public.time_timesheet_entries (profile_id, work_date);

-- ── Ephemeral kiosk sessions ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.kiosk_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_kiosk_sessions_expires
  ON public.kiosk_sessions (expires_at);

-- ── Scope helpers ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.time_clock_profile_in_view_scope(p_target_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p_target_id = auth.uid()
    OR (
      public.get_user_role() IN ('admin'::public.user_role, 'superadmin'::public.user_role)
      AND EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = p_target_id
          AND p.company_id = public.get_user_company_id()
      )
    )
    OR (
      EXISTS (
        SELECT 1
        FROM public.profiles target
        JOIN public.profiles me ON me.id = auth.uid()
        WHERE target.id = p_target_id
          AND target.company_id = me.company_id
          AND target.partner_id IS NULL
          AND (
            public.is_department_leader_of(target.department_id)
            OR (
              me.role = 'leder'::public.user_role
              AND target.department_id IS NOT DISTINCT FROM me.department_id
            )
          )
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.time_clock_can_edit_profile(p_target_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    CASE
      WHEN public.get_user_role() = 'superadmin'::public.user_role THEN TRUE
      WHEN public.is_company_admin() THEN EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = p_target_id
          AND p.company_id = public.get_user_company_id()
      )
      WHEN public.get_user_role() = 'leder'::public.user_role
        OR EXISTS (SELECT 1 FROM public.department_leaders dl WHERE dl.profile_id = auth.uid()) THEN
        p_target_id <> auth.uid()
        AND public.time_clock_profile_in_view_scope(p_target_id)
      ELSE FALSE
    END;
$$;

-- ── Seed default work types ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.seed_time_work_types(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.time_work_types WHERE company_id = p_company_id) THEN
    RETURN;
  END IF;

  INSERT INTO public.time_work_types (company_id, code, name, category, payroll_code, color_hex, is_default_punch, sort_order)
  VALUES
    (p_company_id, '100', 'Lagervakt', 'shift', '1', '#0D9488', TRUE, 10),
    (p_company_id, '110', 'Kjørekontor - dag', 'shift', '1', '#0891B2', FALSE, 20),
    (p_company_id, '111', 'Kjørekontor - kveld', 'shift', '1', '#0284C7', FALSE, 30),
    (p_company_id, '112', 'Kontor', 'shift', '1', '#6366F1', FALSE, 40),
    (p_company_id, '131', 'Ferie', 'absence', '811', '#F59E0B', FALSE, 50),
    (p_company_id, '140', 'Fravær og Permisjon u/lønn', 'absence', '811', '#EF4444', FALSE, 60),
    (p_company_id, '145', 'Fravær og Permisjon m/lønn', 'absence', '811', '#F97316', FALSE, 70),
    (p_company_id, '160', 'Egenmelding', 'absence', '811', '#EC4899', FALSE, 80),
    (p_company_id, '161', 'Egenmelding barns sykdom', 'absence', '811', '#DB2777', FALSE, 90),
    (p_company_id, '170', 'Sykdom Under 16dg m/lønn', 'absence', '811', '#BE185D', FALSE, 100),
    (p_company_id, '175', 'Sykdom over 16dg u/lønn', 'absence', '811', '#9F1239', FALSE, 110),
    (p_company_id, '199', 'Arbeid på røde dager', 'shift', '1', '#7C3AED', FALSE, 120),
    (p_company_id, '200', 'Helligdagsfri med lønn', 'holiday', '811', '#EA580C', FALSE, 130),
    (p_company_id, '500', 'Avspaseringsdag', 'absence', '811', '#65A30D', FALSE, 140);
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_time_clock_company(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slug TEXT;
  v_name TEXT;
  v_default_id UUID;
BEGIN
  PERFORM public.seed_time_work_types(p_company_id);

  IF EXISTS (SELECT 1 FROM public.time_clock_settings WHERE company_id = p_company_id) THEN
    RETURN;
  END IF;

  SELECT lower(regexp_replace(coalesce(c.name, 'bedrift'), '[^a-zA-Z0-9]+', '-', 'g'))
  INTO v_name
  FROM public.companies c
  WHERE c.id = p_company_id;

  v_slug := trim(both '-' from v_name);
  IF length(v_slug) < 3 THEN
    v_slug := 'bedrift-' || left(replace(p_company_id::text, '-', ''), 8);
  END IF;

  WHILE EXISTS (
    SELECT 1 FROM public.time_clock_settings s
    WHERE lower(s.kiosk_slug) = lower(v_slug)
  ) LOOP
    v_slug := v_slug || '-' || floor(random() * 90 + 10)::int;
  END LOOP;

  SELECT id INTO v_default_id
  FROM public.time_work_types
  WHERE company_id = p_company_id AND is_default_punch
  LIMIT 1;

  INSERT INTO public.time_clock_settings (company_id, kiosk_slug, company_display_name, default_work_type_id)
  SELECT p_company_id, v_slug, c.name, v_default_id
  FROM public.companies c
  WHERE c.id = p_company_id;
END;
$$;

-- ── PIN management ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.time_clock_set_pin(
  p_profile_id uuid,
  p_pin text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_emp_no text;
BEGIN
  IF length(trim(coalesce(p_pin, ''))) < 4 OR length(p_pin) > 8 THEN
    RAISE EXCEPTION 'PIN må være 4–8 siffer';
  END IF;

  IF NOT (
    public.get_user_role() = 'superadmin'::public.user_role
    OR public.is_company_admin()
    OR public.time_clock_can_edit_profile(p_profile_id)
    OR p_profile_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  SELECT p.company_id, coalesce(nullif(trim(p.employee_number), ''), ela.employee_number)
  INTO v_company_id, v_emp_no
  FROM public.profiles p
  LEFT JOIN public.employee_login_accounts ela ON ela.profile_id = p.id AND ela.is_active
  WHERE p.id = p_profile_id;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke ansatt';
  END IF;

  IF v_emp_no IS NULL OR trim(v_emp_no) = '' THEN
    RAISE EXCEPTION 'Ansatt mangler ansattnummer';
  END IF;

  INSERT INTO public.time_clock_pins (profile_id, company_id, employee_number, pin_hash, failed_attempts, locked_until)
  VALUES (p_profile_id, v_company_id, trim(v_emp_no), crypt(p_pin, gen_salt('bf')), 0, NULL)
  ON CONFLICT (profile_id) DO UPDATE SET
    employee_number = EXCLUDED.employee_number,
    pin_hash = EXCLUDED.pin_hash,
    failed_attempts = 0,
    locked_until = NULL,
    updated_at = NOW();
END;
$$;

CREATE OR REPLACE FUNCTION public.time_clock_grant_mobile(p_profile_id uuid, p_allowed boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT (
    public.get_user_role() IN ('admin'::public.user_role, 'superadmin'::public.user_role)
    OR public.time_clock_can_edit_profile(p_profile_id)
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  UPDATE public.profiles
  SET time_clock_mobile_allowed = p_allowed
  WHERE id = p_profile_id
    AND company_id = public.get_user_company_id();
END;
$$;

-- ── Kiosk RPCs (anon) ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.kiosk_get_company(p_slug text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.time_clock_settings%ROWTYPE;
BEGIN
  SELECT * INTO v_row
  FROM public.time_clock_settings s
  WHERE lower(s.kiosk_slug) = lower(trim(p_slug))
    AND s.kiosk_enabled = TRUE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ugyldig kiosk');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'company_id', v_row.company_id,
    'display_name', coalesce(v_row.company_display_name, v_row.kiosk_slug),
    'punch_reset_seconds', v_row.punch_reset_seconds
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.kiosk_login(
  p_slug text,
  p_employee_number text,
  p_pin text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_settings public.time_clock_settings%ROWTYPE;
  v_pin_row public.time_clock_pins%ROWTYPE;
  v_profile public.profiles%ROWTYPE;
  v_state public.time_clock_state%ROWTYPE;
  v_session_id uuid;
  v_default_type uuid;
BEGIN
  SELECT * INTO v_settings
  FROM public.time_clock_settings s
  WHERE lower(s.kiosk_slug) = lower(trim(p_slug)) AND s.kiosk_enabled;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ugyldig kiosk');
  END IF;

  SELECT * INTO v_pin_row
  FROM public.time_clock_pins tcp
  WHERE tcp.company_id = v_settings.company_id
    AND trim(tcp.employee_number) = trim(p_employee_number);

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ugyldig ansattnummer eller PIN');
  END IF;

  IF v_pin_row.locked_until IS NOT NULL AND v_pin_row.locked_until > NOW() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Konto midlertidig låst. Prøv igjen senere.');
  END IF;

  IF v_pin_row.pin_hash IS NULL OR v_pin_row.pin_hash <> crypt(p_pin, v_pin_row.pin_hash) THEN
    UPDATE public.time_clock_pins
    SET failed_attempts = failed_attempts + 1,
        locked_until = CASE WHEN failed_attempts + 1 >= 5 THEN NOW() + INTERVAL '15 minutes' ELSE locked_until END
    WHERE profile_id = v_pin_row.profile_id;
    RETURN jsonb_build_object('ok', false, 'error', 'Ugyldig ansattnummer eller PIN');
  END IF;

  UPDATE public.time_clock_pins
  SET failed_attempts = 0, locked_until = NULL, updated_at = NOW()
  WHERE profile_id = v_pin_row.profile_id;

  SELECT * INTO v_profile FROM public.profiles WHERE id = v_pin_row.profile_id;

  SELECT * INTO v_state FROM public.time_clock_state WHERE profile_id = v_pin_row.profile_id;

  v_session_id := gen_random_uuid();
  INSERT INTO public.kiosk_sessions (id, profile_id, company_id, expires_at)
  VALUES (v_session_id, v_pin_row.profile_id, v_settings.company_id, NOW() + INTERVAL '10 minutes');

  v_default_type := v_settings.default_work_type_id;
  IF v_default_type IS NULL THEN
    SELECT id INTO v_default_type
    FROM public.time_work_types
    WHERE company_id = v_settings.company_id AND is_default_punch
    LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'session_token', v_session_id,
    'profile_id', v_profile.id,
    'full_name', v_profile.full_name,
    'is_clocked_in', coalesce(v_state.is_clocked_in, false),
    'clocked_in_at', v_state.clocked_in_at,
    'default_work_type_id', v_default_type,
    'punch_reset_seconds', v_settings.punch_reset_seconds
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.kiosk_get_status(p_session_token uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sess public.kiosk_sessions%ROWTYPE;
  v_state public.time_clock_state%ROWTYPE;
  v_profile public.profiles%ROWTYPE;
BEGIN
  SELECT * INTO v_sess
  FROM public.kiosk_sessions
  WHERE id = p_session_token AND expires_at > NOW();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Sesjon utløpt');
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = v_sess.profile_id;
  SELECT * INTO v_state FROM public.time_clock_state WHERE profile_id = v_sess.profile_id;

  RETURN jsonb_build_object(
    'ok', true,
    'full_name', v_profile.full_name,
    'is_clocked_in', coalesce(v_state.is_clocked_in, false),
    'clocked_in_at', v_state.clocked_in_at,
    'work_type_id', v_state.work_type_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._time_clock_apply_punch(
  p_profile_id uuid,
  p_company_id uuid,
  p_punch_type text,
  p_work_type_id uuid,
  p_source text,
  p_created_by uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := NOW();
  v_state public.time_clock_state%ROWTYPE;
  v_event_id uuid;
  v_open_entry uuid;
  v_hours numeric;
BEGIN
  SELECT * INTO v_state FROM public.time_clock_state WHERE profile_id = p_profile_id;

  IF p_punch_type = 'in' THEN
    IF coalesce(v_state.is_clocked_in, false) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'Allerede innstemplet');
    END IF;

    INSERT INTO public.time_punch_events (profile_id, company_id, punch_type, work_type_id, punched_at, source, created_by)
    VALUES (p_profile_id, p_company_id, 'in', p_work_type_id, v_now, p_source, p_created_by)
    RETURNING id INTO v_event_id;

    INSERT INTO public.time_clock_state (profile_id, company_id, is_clocked_in, work_type_id, clocked_in_at, last_punch_at, updated_at)
    VALUES (p_profile_id, p_company_id, TRUE, p_work_type_id, v_now, v_now, v_now)
    ON CONFLICT (profile_id) DO UPDATE SET
      is_clocked_in = TRUE,
      work_type_id = EXCLUDED.work_type_id,
      clocked_in_at = v_now,
      last_punch_at = v_now,
      updated_at = v_now;

    INSERT INTO public.time_timesheet_entries (
      profile_id, company_id, work_date, work_type_id,
      start_time, hours, source, punch_event_in_id, created_by
    )
    VALUES (
      p_profile_id, p_company_id, (v_now AT TIME ZONE 'Europe/Oslo')::date, p_work_type_id,
      (v_now AT TIME ZONE 'Europe/Oslo')::time, 0, 'punch', v_event_id, p_created_by
    );

    RETURN jsonb_build_object('ok', true, 'punch_type', 'in', 'punched_at', v_now);
  END IF;

  IF NOT coalesce(v_state.is_clocked_in, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ikke innstemplet');
  END IF;

  INSERT INTO public.time_punch_events (profile_id, company_id, punch_type, work_type_id, punched_at, source, created_by)
  VALUES (p_profile_id, p_company_id, 'out', v_state.work_type_id, v_now, p_source, p_created_by)
  RETURNING id INTO v_event_id;

  SELECT id INTO v_open_entry
  FROM public.time_timesheet_entries
  WHERE profile_id = p_profile_id
    AND work_date = (v_now AT TIME ZONE 'Europe/Oslo')::date
    AND punch_event_out_id IS NULL
    AND source = 'punch'
  ORDER BY created_at DESC
  LIMIT 1;

  v_hours := round(
    extract(epoch FROM (v_now - coalesce(v_state.clocked_in_at, v_now))) / 3600.0,
    2
  );

  IF v_open_entry IS NOT NULL THEN
    UPDATE public.time_timesheet_entries
    SET end_time = (v_now AT TIME ZONE 'Europe/Oslo')::time,
        hours = v_hours,
        punch_event_out_id = v_event_id,
        updated_at = v_now,
        updated_by = p_created_by
    WHERE id = v_open_entry;
  END IF;

  UPDATE public.time_clock_state
  SET is_clocked_in = FALSE,
      work_type_id = NULL,
      clocked_in_at = NULL,
      last_punch_at = v_now,
      updated_at = v_now
  WHERE profile_id = p_profile_id;

  RETURN jsonb_build_object('ok', true, 'punch_type', 'out', 'punched_at', v_now, 'hours', v_hours);
END;
$$;

CREATE OR REPLACE FUNCTION public.kiosk_punch(
  p_session_token uuid,
  p_work_type_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sess public.kiosk_sessions%ROWTYPE;
  v_settings public.time_clock_settings%ROWTYPE;
  v_type_id uuid;
  v_result jsonb;
BEGIN
  SELECT * INTO v_sess
  FROM public.kiosk_sessions
  WHERE id = p_session_token AND expires_at > NOW();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Sesjon utløpt');
  END IF;

  SELECT * INTO v_settings FROM public.time_clock_settings WHERE company_id = v_sess.company_id;

  v_type_id := coalesce(
    p_work_type_id,
    v_settings.default_work_type_id,
    (SELECT id FROM public.time_work_types WHERE company_id = v_sess.company_id AND is_default_punch LIMIT 1)
  );

  SELECT public._time_clock_apply_punch(
    v_sess.profile_id,
    v_sess.company_id,
    CASE WHEN coalesce((SELECT is_clocked_in FROM public.time_clock_state WHERE profile_id = v_sess.profile_id), false)
      THEN 'out' ELSE 'in' END,
    v_type_id,
    'kiosk',
    NULL
  ) INTO v_result;

  IF (v_result->>'ok')::boolean THEN
    UPDATE public.kiosk_sessions SET expires_at = NOW() + INTERVAL '2 minutes' WHERE id = p_session_token;
  END IF;

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.time_clock_punch_mobile(p_work_type_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile public.profiles%ROWTYPE;
  v_type_id uuid;
  v_is_in boolean;
BEGIN
  SELECT * INTO v_profile FROM public.profiles WHERE id = auth.uid();
  IF NOT FOUND OR NOT v_profile.time_clock_mobile_allowed THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Mobilstempling ikke aktivert');
  END IF;

  PERFORM public.ensure_time_clock_company(v_profile.company_id);

  v_type_id := coalesce(
    p_work_type_id,
    (SELECT default_work_type_id FROM public.time_clock_settings WHERE company_id = v_profile.company_id),
    (SELECT id FROM public.time_work_types WHERE company_id = v_profile.company_id AND is_default_punch LIMIT 1)
  );

  SELECT coalesce(is_clocked_in, false) INTO v_is_in
  FROM public.time_clock_state WHERE profile_id = v_profile.id;

  RETURN public._time_clock_apply_punch(
    v_profile.id,
    v_profile.company_id,
    CASE WHEN v_is_in THEN 'out' ELSE 'in' END,
    v_type_id,
    'mobile',
    v_profile.id
  );
END;
$$;

-- ── Admin queries ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.time_clock_list_presence(
  p_department_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid := public.get_user_company_id();
  v_result jsonb;
BEGIN
  IF v_company_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  IF NOT (
    public.get_user_role() IN ('admin'::public.user_role, 'superadmin'::public.user_role, 'leder'::public.user_role)
    OR EXISTS (SELECT 1 FROM public.department_leaders dl WHERE dl.profile_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.last_name, t.first_name), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      p.id AS profile_id,
      p.full_name,
      split_part(coalesce(p.full_name, ''), ' ', 1) AS first_name,
      nullif(regexp_replace(coalesce(p.full_name, ''), '^\S+\s*', ''), '') AS last_name,
      coalesce(p.employee_number, tcp.employee_number) AS employee_number,
      p.department_id,
      d.name AS department_name,
      coalesce(s.is_clocked_in, false) AS is_clocked_in,
      s.clocked_in_at,
      wt.code AS work_type_code,
      wt.name AS work_type_name,
      wt.color_hex AS work_type_color
    FROM public.profiles p
    LEFT JOIN public.time_clock_state s ON s.profile_id = p.id
    LEFT JOIN public.time_clock_pins tcp ON tcp.profile_id = p.id
    LEFT JOIN public.time_work_types wt ON wt.id = s.work_type_id
    LEFT JOIN public.departments d ON d.id = p.department_id
    WHERE p.company_id = v_company_id
      AND p.partner_id IS NULL
      AND p.is_approved = TRUE
      AND (p_department_id IS NULL OR p.department_id = p_department_id)
      AND (
        public.get_user_role() IN ('admin'::public.user_role, 'superadmin'::public.user_role)
        OR public.time_clock_profile_in_view_scope(p.id)
      )
  ) t;

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.time_clock_upsert_entry(p_payload jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid := nullif(p_payload->>'id', '')::uuid;
  v_profile_id uuid := (p_payload->>'profile_id')::uuid;
  v_company_id uuid;
  v_hours numeric := coalesce((p_payload->>'hours')::numeric, 0);
BEGIN
  IF NOT public.time_clock_can_edit_profile(v_profile_id) THEN
    RAISE EXCEPTION 'Ingen tilgang til å redigere denne ansatte';
  END IF;

  SELECT company_id INTO v_company_id FROM public.profiles WHERE id = v_profile_id;

  IF v_id IS NULL THEN
    INSERT INTO public.time_timesheet_entries (
      profile_id, company_id, work_date, work_type_id,
      start_time, end_time, hours, department_id,
      project, activity, invoice_note, note,
      source, created_by, updated_by
    )
    VALUES (
      v_profile_id,
      v_company_id,
      (p_payload->>'work_date')::date,
      (p_payload->>'work_type_id')::uuid,
      nullif(p_payload->>'start_time', '')::time,
      nullif(p_payload->>'end_time', '')::time,
      v_hours,
      nullif(p_payload->>'department_id', '')::uuid,
      nullif(p_payload->>'project', ''),
      nullif(p_payload->>'activity', ''),
      nullif(p_payload->>'invoice_note', ''),
      nullif(p_payload->>'note', ''),
      'manual',
      auth.uid(),
      auth.uid()
    )
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.time_timesheet_entries e
    SET work_date = (p_payload->>'work_date')::date,
        work_type_id = (p_payload->>'work_type_id')::uuid,
        start_time = nullif(p_payload->>'start_time', '')::time,
        end_time = nullif(p_payload->>'end_time', '')::time,
        hours = v_hours,
        department_id = nullif(p_payload->>'department_id', '')::uuid,
        project = nullif(p_payload->>'project', ''),
        activity = nullif(p_payload->>'activity', ''),
        invoice_note = nullif(p_payload->>'invoice_note', ''),
        note = nullif(p_payload->>'note', ''),
        updated_by = auth.uid(),
        updated_at = NOW()
    WHERE e.id = v_id
      AND e.profile_id = v_profile_id
      AND e.is_locked = FALSE;
  END IF;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.time_clock_delete_entry(p_entry_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile_id uuid;
BEGIN
  SELECT profile_id INTO v_profile_id
  FROM public.time_timesheet_entries WHERE id = p_entry_id;

  IF NOT public.time_clock_can_edit_profile(v_profile_id) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  DELETE FROM public.time_timesheet_entries
  WHERE id = p_entry_id AND is_locked = FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION public.time_clock_get_settings()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid := public.get_user_company_id();
  v_row public.time_clock_settings%ROWTYPE;
BEGIN
  IF v_company_id IS NULL THEN
    RETURN jsonb_build_object('ok', false);
  END IF;

  PERFORM public.ensure_time_clock_company(v_company_id);
  SELECT * INTO v_row FROM public.time_clock_settings WHERE company_id = v_company_id;

  RETURN jsonb_build_object(
    'ok', true,
    'kiosk_slug', v_row.kiosk_slug,
    'kiosk_enabled', v_row.kiosk_enabled,
    'display_name', v_row.company_display_name,
    'punch_reset_seconds', v_row.punch_reset_seconds,
    'kiosk_url', '/kiosk/' || v_row.kiosk_slug
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.time_clock_update_settings(p_payload jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid := public.get_user_company_id();
BEGIN
  IF NOT public.is_company_admin() AND public.get_user_role() <> 'superadmin'::public.user_role THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  PERFORM public.ensure_time_clock_company(v_company_id);

  UPDATE public.time_clock_settings
  SET kiosk_slug = coalesce(nullif(trim(p_payload->>'kiosk_slug'), ''), kiosk_slug),
      kiosk_enabled = coalesce((p_payload->>'kiosk_enabled')::boolean, kiosk_enabled),
      company_display_name = coalesce(nullif(p_payload->>'display_name', ''), company_display_name),
      punch_reset_seconds = greatest(2, least(30, coalesce((p_payload->>'punch_reset_seconds')::int, punch_reset_seconds))),
      updated_at = NOW()
  WHERE company_id = v_company_id;
END;
$$;

-- ── RLS ───────────────────────────────────────────────────────────────────────

ALTER TABLE public.time_clock_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.time_work_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.time_clock_pins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.time_clock_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.time_punch_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.time_timesheet_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kiosk_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS time_clock_settings_read ON public.time_clock_settings;
CREATE POLICY time_clock_settings_read ON public.time_clock_settings
  FOR SELECT TO authenticated
  USING (company_id = public.get_user_company_id());

DROP POLICY IF EXISTS time_clock_settings_admin ON public.time_clock_settings;
CREATE POLICY time_clock_settings_admin ON public.time_clock_settings
  FOR ALL TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (public.is_company_admin() OR public.get_user_role() = 'superadmin'::public.user_role)
  );

DROP POLICY IF EXISTS time_work_types_read ON public.time_work_types;
CREATE POLICY time_work_types_read ON public.time_work_types
  FOR SELECT TO authenticated
  USING (company_id = public.get_user_company_id());

DROP POLICY IF EXISTS time_work_types_admin ON public.time_work_types;
CREATE POLICY time_work_types_admin ON public.time_work_types
  FOR ALL TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (public.is_company_admin() OR public.get_user_role() = 'superadmin'::public.user_role)
  );

DROP POLICY IF EXISTS time_clock_pins_admin ON public.time_clock_pins;
CREATE POLICY time_clock_pins_admin ON public.time_clock_pins
  FOR SELECT TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      profile_id = auth.uid()
      OR public.is_company_admin()
      OR public.get_user_role() = 'superadmin'::public.user_role
      OR public.time_clock_can_edit_profile(profile_id)
    )
  );

DROP POLICY IF EXISTS time_clock_state_read ON public.time_clock_state;
CREATE POLICY time_clock_state_read ON public.time_clock_state
  FOR SELECT TO authenticated
  USING (
    profile_id = auth.uid()
    OR public.time_clock_profile_in_view_scope(profile_id)
  );

DROP POLICY IF EXISTS time_punch_events_read ON public.time_punch_events;
CREATE POLICY time_punch_events_read ON public.time_punch_events
  FOR SELECT TO authenticated
  USING (
    profile_id = auth.uid()
    OR public.time_clock_profile_in_view_scope(profile_id)
  );

DROP POLICY IF EXISTS time_timesheet_read ON public.time_timesheet_entries;
CREATE POLICY time_timesheet_read ON public.time_timesheet_entries
  FOR SELECT TO authenticated
  USING (
    profile_id = auth.uid()
    OR public.time_clock_profile_in_view_scope(profile_id)
  );

DROP POLICY IF EXISTS time_timesheet_write ON public.time_timesheet_entries;
CREATE POLICY time_timesheet_write ON public.time_timesheet_entries
  FOR ALL TO authenticated
  USING (public.time_clock_can_edit_profile(profile_id))
  WITH CHECK (public.time_clock_can_edit_profile(profile_id));

-- Kiosk sessions: no direct client access
REVOKE ALL ON public.kiosk_sessions FROM anon, authenticated;

-- Grants
GRANT SELECT ON public.time_clock_settings TO authenticated;
GRANT SELECT ON public.time_work_types TO authenticated;
GRANT SELECT ON public.time_clock_pins TO authenticated;
GRANT SELECT ON public.time_clock_state TO authenticated;
GRANT SELECT ON public.time_punch_events TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.time_timesheet_entries TO authenticated;

GRANT EXECUTE ON FUNCTION public.kiosk_get_company(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.kiosk_login(text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.kiosk_get_status(uuid) TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.kiosk_get_work_types(p_session_token uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sess public.kiosk_sessions%ROWTYPE;
BEGIN
  SELECT * INTO v_sess
  FROM public.kiosk_sessions
  WHERE id = p_session_token AND expires_at > NOW();

  IF NOT FOUND THEN
    RETURN '[]'::jsonb;
  END IF;

  RETURN coalesce((
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', wt.id,
        'code', wt.code,
        'name', wt.name,
        'color_hex', wt.color_hex,
        'is_default_punch', wt.is_default_punch
      ) ORDER BY wt.sort_order
    )
    FROM public.time_work_types wt
    WHERE wt.company_id = v_sess.company_id AND wt.is_active
  ), '[]'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.kiosk_punch(uuid, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.kiosk_get_work_types(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.time_clock_punch_mobile(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.time_clock_list_presence(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.time_clock_upsert_entry(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.time_clock_delete_entry(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.time_clock_set_pin(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.time_clock_grant_mobile(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.time_clock_get_settings() TO authenticated;
GRANT EXECUTE ON FUNCTION public.time_clock_update_settings(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_time_clock_company(uuid) TO authenticated;

-- Seed existing companies
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.companies LOOP
    PERFORM public.ensure_time_clock_company(r.id);
  END LOOP;
END $$;
