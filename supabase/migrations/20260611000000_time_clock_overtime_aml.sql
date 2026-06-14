-- Overtid etter arbeidsmiljøloven §10-4 (alminnelig arbeidstid) og §10-6 (overtid)

-- ── Innstillinger ─────────────────────────────────────────────────────────────

ALTER TABLE public.time_clock_settings
  ADD COLUMN IF NOT EXISTS daily_work_limit_hours NUMERIC(4, 2) NOT NULL DEFAULT 9,
  ADD COLUMN IF NOT EXISTS weekly_work_limit_hours NUMERIC(4, 2) NOT NULL DEFAULT 40,
  ADD COLUMN IF NOT EXISTS overtime_supplement_pct NUMERIC(5, 2) NOT NULL DEFAULT 40,
  ADD COLUMN IF NOT EXISTS overtime_regime TEXT NOT NULL DEFAULT 'standard'
    CHECK (overtime_regime IN ('standard', 'tariff')),
  ADD COLUMN IF NOT EXISTS overtime_weekly_max NUMERIC(5, 2) NOT NULL DEFAULT 10,
  ADD COLUMN IF NOT EXISTS overtime_four_week_max NUMERIC(5, 2) NOT NULL DEFAULT 25,
  ADD COLUMN IF NOT EXISTS overtime_annual_max NUMERIC(6, 2) NOT NULL DEFAULT 200;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS time_agreed_weekly_hours NUMERIC(4, 2) DEFAULT 37.5,
  ADD COLUMN IF NOT EXISTS time_overtime_exempt BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.time_timesheet_entries
  ADD COLUMN IF NOT EXISTS regular_hours NUMERIC(6, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS overtime_hours NUMERIC(6, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS overtime_reason TEXT;

-- Utvid arbeidstype-kategori med overtid
ALTER TABLE public.time_work_types
  DROP CONSTRAINT IF EXISTS time_work_types_category_check;

ALTER TABLE public.time_work_types
  ADD CONSTRAINT time_work_types_category_check
  CHECK (category IN ('shift', 'absence', 'holiday', 'overtime', 'other'));

-- ── Seed overtid-arbeidstype ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.seed_time_overtime_work_type(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.time_work_types
    WHERE company_id = p_company_id AND code = '210'
  ) THEN
    RETURN;
  END IF;

  INSERT INTO public.time_work_types (
    company_id, code, name, category, payroll_code, color_hex, is_default_punch, sort_order
  )
  VALUES (
    p_company_id, '210', 'Overtid', 'overtime', '210', '#DC2626', FALSE, 125
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.seed_time_work_types(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.time_work_types WHERE company_id = p_company_id) THEN
    PERFORM public.seed_time_overtime_work_type(p_company_id);
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
    (p_company_id, '210', 'Overtid', 'overtime', '210', '#DC2626', FALSE, 125),
    (p_company_id, '200', 'Helligdagsfri med lønn', 'holiday', '811', '#EA580C', FALSE, 130),
    (p_company_id, '500', 'Avspaseringsdag', 'absence', '811', '#65A30D', FALSE, 140);
END;
$$;

-- ── Hjelpefunksjoner ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.time_clock_week_monday(p_date date)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_date - ((extract(isodow FROM p_date)::int - 1) || ' days')::interval;
$$;

CREATE OR REPLACE FUNCTION public.time_clock_entry_counts_toward_overtime(p_entry_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(wt.category IN ('shift', 'overtime'), false)
  FROM public.time_timesheet_entries e
  JOIN public.time_work_types wt ON wt.id = e.work_type_id
  WHERE e.id = p_entry_id;
$$;

CREATE OR REPLACE FUNCTION public.time_clock_apply_overtime_regime(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.time_clock_settings
  SET
    overtime_weekly_max = CASE WHEN overtime_regime = 'tariff' THEN 20 ELSE 10 END,
    overtime_four_week_max = CASE WHEN overtime_regime = 'tariff' THEN 50 ELSE 25 END,
    overtime_annual_max = CASE WHEN overtime_regime = 'tariff' THEN 300 ELSE 200 END,
    updated_at = NOW()
  WHERE company_id = p_company_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.time_clock_recalc_overtime(
  p_profile_id uuid,
  p_week_start date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_exempt boolean;
  v_daily_limit numeric;
  v_weekly_limit numeric;
  v_week_start date;
  v_week_end date;
  r record;
  v_day_shift numeric;
  v_week_shift numeric;
  v_regular numeric;
  v_overtime numeric;
BEGIN
  SELECT p.company_id, coalesce(p.time_overtime_exempt, false)
  INTO v_company_id, v_exempt
  FROM public.profiles p
  WHERE p.id = p_profile_id;

  IF v_company_id IS NULL OR v_exempt THEN
    UPDATE public.time_timesheet_entries
    SET regular_hours = hours, overtime_hours = 0
    WHERE profile_id = p_profile_id
      AND (p_week_start IS NULL OR work_date BETWEEN p_week_start AND p_week_start + 6);
    RETURN;
  END IF;

  SELECT
    coalesce(s.daily_work_limit_hours, 9),
    coalesce(s.weekly_work_limit_hours, 40)
  INTO v_daily_limit, v_weekly_limit
  FROM public.time_clock_settings s
  WHERE s.company_id = v_company_id;

  IF p_week_start IS NULL THEN
    v_week_start := public.time_clock_week_monday(current_date);
  ELSE
    v_week_start := p_week_start;
  END IF;
  v_week_end := v_week_start + 6;

  UPDATE public.time_timesheet_entries e
  SET regular_hours = e.hours, overtime_hours = 0
  WHERE e.profile_id = p_profile_id
    AND e.work_date BETWEEN v_week_start AND v_week_end;

  v_week_shift := 0;

  FOR r IN
    SELECT
      e.id,
      e.work_date,
      e.hours,
      wt.category
    FROM public.time_timesheet_entries e
    JOIN public.time_work_types wt ON wt.id = e.work_type_id
    WHERE e.profile_id = p_profile_id
      AND e.work_date BETWEEN v_week_start AND v_week_end
      AND wt.category IN ('shift', 'overtime')
    ORDER BY e.work_date, coalesce(e.start_time, '00:00:00'::time), e.created_at
  LOOP
    SELECT coalesce(sum(sub.hours), 0)
    INTO v_day_shift
    FROM public.time_timesheet_entries sub
    JOIN public.time_work_types wt2 ON wt2.id = sub.work_type_id
    WHERE sub.profile_id = p_profile_id
      AND sub.work_date = r.work_date
      AND sub.id <> r.id
      AND wt2.category IN ('shift', 'overtime');

    v_regular := least(
      r.hours,
      greatest(0, v_daily_limit - v_day_shift),
      greatest(0, v_weekly_limit - v_week_shift)
    );
    v_overtime := greatest(0, r.hours - v_regular);

    UPDATE public.time_timesheet_entries
    SET regular_hours = round(v_regular, 2),
        overtime_hours = round(v_overtime, 2)
    WHERE id = r.id;

    v_week_shift := v_week_shift + r.hours;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.time_clock_overtime_summary(
  p_profile_id uuid,
  p_week_start date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_exempt boolean;
  v_settings public.time_clock_settings%ROWTYPE;
  v_week_end date;
  v_week_shift numeric := 0;
  v_week_regular numeric := 0;
  v_week_overtime numeric := 0;
  v_supplement_hours numeric := 0;
  v_four_week_overtime numeric := 0;
  v_annual_overtime numeric := 0;
  v_daily jsonb;
  v_limits jsonb;
BEGIN
  IF NOT (
    p_profile_id = auth.uid()
    OR public.time_clock_profile_in_view_scope(p_profile_id)
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  PERFORM public.time_clock_recalc_overtime(p_profile_id, p_week_start);

  SELECT p.company_id, coalesce(p.time_overtime_exempt, false)
  INTO v_company_id, v_exempt
  FROM public.profiles p
  WHERE p.id = p_profile_id;

  SELECT * INTO v_settings FROM public.time_clock_settings WHERE company_id = v_company_id;
  v_week_end := p_week_start + 6;

  SELECT
    coalesce(sum(e.hours), 0),
    coalesce(sum(e.regular_hours), 0),
    coalesce(sum(e.overtime_hours), 0)
  INTO v_week_shift, v_week_regular, v_week_overtime
  FROM public.time_timesheet_entries e
  JOIN public.time_work_types wt ON wt.id = e.work_type_id
  WHERE e.profile_id = p_profile_id
    AND e.work_date BETWEEN p_week_start AND v_week_end
    AND wt.category IN ('shift', 'overtime');

  v_supplement_hours := round(v_week_overtime * coalesce(v_settings.overtime_supplement_pct, 40) / 100.0, 2);

  SELECT coalesce(sum(e.overtime_hours), 0)
  INTO v_four_week_overtime
  FROM public.time_timesheet_entries e
  JOIN public.time_work_types wt ON wt.id = e.work_type_id
  WHERE e.profile_id = p_profile_id
    AND e.work_date BETWEEN (p_week_start - 21) AND v_week_end
    AND wt.category IN ('shift', 'overtime');

  SELECT coalesce(sum(e.overtime_hours), 0)
  INTO v_annual_overtime
  FROM public.time_timesheet_entries e
  JOIN public.time_work_types wt ON wt.id = e.work_type_id
  WHERE e.profile_id = p_profile_id
    AND e.work_date BETWEEN (p_week_start - 364) AND v_week_end
    AND wt.category IN ('shift', 'overtime');

  SELECT coalesce(jsonb_agg(day_row ORDER BY day_row->>'date'), '[]'::jsonb)
  INTO v_daily
  FROM (
    SELECT jsonb_build_object(
      'date', d::text,
      'shift_hours', coalesce((
        SELECT sum(e.hours)
        FROM public.time_timesheet_entries e
        JOIN public.time_work_types wt ON wt.id = e.work_type_id
        WHERE e.profile_id = p_profile_id
          AND e.work_date = d
          AND wt.category IN ('shift', 'overtime')
      ), 0),
      'regular_hours', coalesce((
        SELECT sum(e.regular_hours)
        FROM public.time_timesheet_entries e
        JOIN public.time_work_types wt ON wt.id = e.work_type_id
        WHERE e.profile_id = p_profile_id
          AND e.work_date = d
          AND wt.category IN ('shift', 'overtime')
      ), 0),
      'overtime_hours', coalesce((
        SELECT sum(e.overtime_hours)
        FROM public.time_timesheet_entries e
        JOIN public.time_work_types wt ON wt.id = e.work_type_id
        WHERE e.profile_id = p_profile_id
          AND e.work_date = d
          AND wt.category IN ('shift', 'overtime')
      ), 0),
      'daily_limit', coalesce(v_settings.daily_work_limit_hours, 9),
      'exceeds_daily_limit', coalesce((
        SELECT sum(e.hours) > coalesce(v_settings.daily_work_limit_hours, 9)
        FROM public.time_timesheet_entries e
        JOIN public.time_work_types wt ON wt.id = e.work_type_id
        WHERE e.profile_id = p_profile_id
          AND e.work_date = d
          AND wt.category IN ('shift', 'overtime')
      ), false)
    ) AS day_row
    FROM generate_series(p_week_start, v_week_end, '1 day'::interval) AS d
  ) days;

  v_limits := jsonb_build_object(
    'weekly_overtime', v_week_overtime,
    'weekly_max', coalesce(v_settings.overtime_weekly_max, 10),
    'weekly_exceeded', v_week_overtime > coalesce(v_settings.overtime_weekly_max, 10),
    'four_week_overtime', v_four_week_overtime,
    'four_week_max', coalesce(v_settings.overtime_four_week_max, 25),
    'four_week_exceeded', v_four_week_overtime > coalesce(v_settings.overtime_four_week_max, 25),
    'annual_overtime', v_annual_overtime,
    'annual_max', coalesce(v_settings.overtime_annual_max, 200),
    'annual_exceeded', v_annual_overtime > coalesce(v_settings.overtime_annual_max, 200)
  );

  RETURN jsonb_build_object(
    'ok', true,
    'week_start', p_week_start,
    'week_end', v_week_end,
    'exempt', v_exempt,
    'legal', jsonb_build_object(
      'daily_limit_hours', coalesce(v_settings.daily_work_limit_hours, 9),
      'weekly_limit_hours', coalesce(v_settings.weekly_work_limit_hours, 40),
      'overtime_supplement_pct', coalesce(v_settings.overtime_supplement_pct, 40),
      'overtime_regime', coalesce(v_settings.overtime_regime, 'standard'),
      'references', jsonb_build_array('aml_10_4', 'aml_10_6')
    ),
    'week_shift_hours', round(v_week_shift, 2),
    'week_regular_hours', round(v_week_regular, 2),
    'week_overtime_hours', round(v_week_overtime, 2),
    'week_supplement_hours', v_supplement_hours,
    'agreed_weekly_hours', (
      SELECT time_agreed_weekly_hours FROM public.profiles WHERE id = p_profile_id
    ),
    'daily', v_daily,
    'limits', v_limits
  );
END;
$$;

-- ── Oppdater stempling ──────────────────────────────────────────────────────────

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
  v_work_date date;
  v_week_start date;
  v_overtime numeric;
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
      start_time, hours, regular_hours, source, punch_event_in_id, created_by
    )
    VALUES (
      p_profile_id, p_company_id, (v_now AT TIME ZONE 'Europe/Oslo')::date, p_work_type_id,
      (v_now AT TIME ZONE 'Europe/Oslo')::time, 0, 0, 'punch', v_event_id, p_created_by
    );

    RETURN jsonb_build_object('ok', true, 'punch_type', 'in', 'punched_at', v_now);
  END IF;

  IF NOT coalesce(v_state.is_clocked_in, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ikke innstemplet');
  END IF;

  INSERT INTO public.time_punch_events (profile_id, company_id, punch_type, work_type_id, punched_at, source, created_by)
  VALUES (p_profile_id, p_company_id, 'out', v_state.work_type_id, v_now, p_source, p_created_by)
  RETURNING id INTO v_event_id;

  v_work_date := (v_now AT TIME ZONE 'Europe/Oslo')::date;
  v_week_start := public.time_clock_week_monday(v_work_date);

  SELECT id INTO v_open_entry
  FROM public.time_timesheet_entries
  WHERE profile_id = p_profile_id
    AND work_date = v_work_date
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

  PERFORM public.time_clock_recalc_overtime(p_profile_id, v_week_start);

  SELECT coalesce(sum(overtime_hours), 0)
  INTO v_overtime
  FROM public.time_timesheet_entries
  WHERE id = v_open_entry;

  UPDATE public.time_clock_state
  SET is_clocked_in = FALSE,
      work_type_id = NULL,
      clocked_in_at = NULL,
      last_punch_at = v_now,
      updated_at = v_now
  WHERE profile_id = p_profile_id;

  RETURN jsonb_build_object(
    'ok', true,
    'punch_type', 'out',
    'punched_at', v_now,
    'hours', v_hours,
    'overtime_hours', coalesce(v_overtime, 0),
    'week_start', v_week_start
  );
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
  v_work_date date := (p_payload->>'work_date')::date;
  v_week_start date;
BEGIN
  IF NOT public.time_clock_can_edit_profile(v_profile_id) THEN
    RAISE EXCEPTION 'Ingen tilgang til å redigere denne ansatte';
  END IF;

  SELECT company_id INTO v_company_id FROM public.profiles WHERE id = v_profile_id;
  v_week_start := public.time_clock_week_monday(v_work_date);

  IF v_id IS NULL THEN
    INSERT INTO public.time_timesheet_entries (
      profile_id, company_id, work_date, work_type_id,
      start_time, end_time, hours, regular_hours, department_id,
      project, activity, invoice_note, note, overtime_reason,
      source, created_by, updated_by
    )
    VALUES (
      v_profile_id,
      v_company_id,
      v_work_date,
      (p_payload->>'work_type_id')::uuid,
      nullif(p_payload->>'start_time', '')::time,
      nullif(p_payload->>'end_time', '')::time,
      v_hours,
      v_hours,
      nullif(p_payload->>'department_id', '')::uuid,
      nullif(p_payload->>'project', ''),
      nullif(p_payload->>'activity', ''),
      nullif(p_payload->>'invoice_note', ''),
      nullif(p_payload->>'note', ''),
      nullif(p_payload->>'overtime_reason', ''),
      'manual',
      auth.uid(),
      auth.uid()
    )
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.time_timesheet_entries e
    SET work_date = v_work_date,
        work_type_id = (p_payload->>'work_type_id')::uuid,
        start_time = nullif(p_payload->>'start_time', '')::time,
        end_time = nullif(p_payload->>'end_time', '')::time,
        hours = v_hours,
        department_id = nullif(p_payload->>'department_id', '')::uuid,
        project = nullif(p_payload->>'project', ''),
        activity = nullif(p_payload->>'activity', ''),
        invoice_note = nullif(p_payload->>'invoice_note', ''),
        note = nullif(p_payload->>'note', ''),
        overtime_reason = nullif(p_payload->>'overtime_reason', ''),
        updated_by = auth.uid(),
        updated_at = NOW()
    WHERE e.id = v_id
      AND e.profile_id = v_profile_id
      AND e.is_locked = FALSE;
  END IF;

  PERFORM public.time_clock_recalc_overtime(v_profile_id, v_week_start);
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
  v_work_date date;
BEGIN
  SELECT profile_id, work_date INTO v_profile_id, v_work_date
  FROM public.time_timesheet_entries WHERE id = p_entry_id;

  IF NOT public.time_clock_can_edit_profile(v_profile_id) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  DELETE FROM public.time_timesheet_entries
  WHERE id = p_entry_id AND is_locked = FALSE;

  PERFORM public.time_clock_recalc_overtime(
    v_profile_id,
    public.time_clock_week_monday(v_work_date)
  );
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
    'kiosk_url', '/kiosk/' || v_row.kiosk_slug,
    'overtime', jsonb_build_object(
      'daily_work_limit_hours', v_row.daily_work_limit_hours,
      'weekly_work_limit_hours', v_row.weekly_work_limit_hours,
      'overtime_supplement_pct', v_row.overtime_supplement_pct,
      'overtime_regime', v_row.overtime_regime,
      'overtime_weekly_max', v_row.overtime_weekly_max,
      'overtime_four_week_max', v_row.overtime_four_week_max,
      'overtime_annual_max', v_row.overtime_annual_max
    )
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
  v_regime text;
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
      daily_work_limit_hours = greatest(1, least(13, coalesce((p_payload->'overtime'->>'daily_work_limit_hours')::numeric, daily_work_limit_hours))),
      weekly_work_limit_hours = greatest(1, least(48, coalesce((p_payload->'overtime'->>'weekly_work_limit_hours')::numeric, weekly_work_limit_hours))),
      overtime_supplement_pct = greatest(40, coalesce((p_payload->'overtime'->>'overtime_supplement_pct')::numeric, overtime_supplement_pct)),
      overtime_regime = coalesce(nullif(p_payload->'overtime'->>'overtime_regime', ''), overtime_regime),
      updated_at = NOW()
  WHERE company_id = v_company_id;

  v_regime := coalesce(nullif(p_payload->'overtime'->>'overtime_regime', ''), 'standard');
  IF v_regime IN ('standard', 'tariff') THEN
    UPDATE public.time_clock_settings
    SET
      overtime_weekly_max = CASE WHEN v_regime = 'tariff' THEN 20 ELSE 10 END,
      overtime_four_week_max = CASE WHEN v_regime = 'tariff' THEN 50 ELSE 25 END,
      overtime_annual_max = CASE WHEN v_regime = 'tariff' THEN 300 ELSE 200 END
    WHERE company_id = v_company_id;
  END IF;
END;
$$;

-- Seed overtid for eksisterende bedrifter
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.companies LOOP
    PERFORM public.seed_time_overtime_work_type(r.id);
  END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION public.time_clock_overtime_summary(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.time_clock_recalc_overtime(uuid, date) TO authenticated;
