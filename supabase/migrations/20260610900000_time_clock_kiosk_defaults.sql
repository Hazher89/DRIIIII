-- Kiosk: standard-PIN 0, /stemple-støtte, auto-provisjonering ved innlogging

CREATE OR REPLACE FUNCTION public.time_clock_default_pin()
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT '0';
$$;

CREATE OR REPLACE FUNCTION public.time_clock_profile_employee_number(p_profile_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT trim(coalesce(
    nullif(trim(p.employee_number), ''),
    nullif(trim(ela.employee_number), '')
  ))
  FROM public.profiles p
  LEFT JOIN public.employee_login_accounts ela
    ON ela.profile_id = p.id AND ela.is_active
  WHERE p.id = p_profile_id;
$$;

CREATE OR REPLACE FUNCTION public.time_clock_sync_default_pins_internal(p_company_id uuid)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count int := 0;
BEGIN
  INSERT INTO public.time_clock_pins (profile_id, company_id, employee_number, pin_hash, failed_attempts, locked_until)
  SELECT
    p.id,
    p.company_id,
    public.time_clock_profile_employee_number(p.id),
    crypt(public.time_clock_default_pin(), gen_salt('bf')),
    0,
    NULL
  FROM public.profiles p
  WHERE p.company_id = p_company_id
    AND p.partner_id IS NULL
    AND coalesce(p.is_active, true)
    AND public.time_clock_profile_employee_number(p.id) IS NOT NULL
    AND length(public.time_clock_profile_employee_number(p.id)) > 0
  ON CONFLICT (profile_id) DO UPDATE SET
    employee_number = EXCLUDED.employee_number,
    pin_hash = crypt(public.time_clock_default_pin(), gen_salt('bf')),
    failed_attempts = 0,
    locked_until = NULL,
    updated_at = NOW();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.time_clock_sync_default_pins(p_company_id uuid DEFAULT NULL)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid := coalesce(p_company_id, public.get_user_company_id());
BEGIN
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Mangler bedrift';
  END IF;

  IF NOT (
    public.get_user_role() IN ('admin'::public.user_role, 'superadmin'::public.user_role)
    OR public.is_company_admin()
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  RETURN public.time_clock_sync_default_pins_internal(v_company_id);
END;
$$;

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
  IF length(trim(coalesce(p_pin, ''))) < 1 OR length(p_pin) > 8 THEN
    RAISE EXCEPTION 'PIN må være 1–8 siffer';
  END IF;

  IF NOT (
    public.get_user_role() = 'superadmin'::public.user_role
    OR public.is_company_admin()
    OR public.time_clock_can_edit_profile(p_profile_id)
    OR p_profile_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  v_emp_no := public.time_clock_profile_employee_number(p_profile_id);
  SELECT p.company_id INTO v_company_id FROM public.profiles p WHERE p.id = p_profile_id;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke ansatt';
  END IF;

  IF v_emp_no IS NULL OR trim(v_emp_no) = '' THEN
    RAISE EXCEPTION 'Ansatt mangler ansattnummer';
  END IF;

  INSERT INTO public.time_clock_pins (profile_id, company_id, employee_number, pin_hash, failed_attempts, locked_until)
  VALUES (p_profile_id, v_company_id, v_emp_no, crypt(p_pin, gen_salt('bf')), 0, NULL)
  ON CONFLICT (profile_id) DO UPDATE SET
    employee_number = EXCLUDED.employee_number,
    pin_hash = EXCLUDED.pin_hash,
    failed_attempts = 0,
    locked_until = NULL,
    updated_at = NOW();
END;
$$;

CREATE OR REPLACE FUNCTION public.kiosk_get_company(p_slug text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.time_clock_settings%ROWTYPE;
  v_slug text := lower(trim(coalesce(p_slug, '')));
BEGIN
  IF v_slug = '' OR v_slug = 'stemple' THEN
    SELECT * INTO v_row
    FROM public.time_clock_settings s
    WHERE s.kiosk_enabled = TRUE
    ORDER BY CASE WHEN lower(s.kiosk_slug) = 'stemple' THEN 0 ELSE 1 END, s.created_at
    LIMIT 1;
  ELSE
    SELECT * INTO v_row
    FROM public.time_clock_settings s
    WHERE lower(s.kiosk_slug) = v_slug
      AND s.kiosk_enabled = TRUE;
  END IF;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ugyldig kiosk');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'company_id', v_row.company_id,
    'display_name', coalesce(v_row.company_display_name, v_row.kiosk_slug),
    'punch_reset_seconds', v_row.punch_reset_seconds,
    'kiosk_slug', v_row.kiosk_slug
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
  v_slug text := lower(trim(coalesce(p_slug, '')));
  v_emp text := trim(coalesce(p_employee_number, ''));
  v_pin text := coalesce(nullif(trim(p_pin), ''), public.time_clock_default_pin());
BEGIN
  IF v_emp = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Angi ansattnummer');
  END IF;

  IF v_slug = '' OR v_slug = 'stemple' THEN
    SELECT * INTO v_settings
    FROM public.time_clock_settings s
    WHERE s.kiosk_enabled
    ORDER BY CASE WHEN lower(s.kiosk_slug) = 'stemple' THEN 0 ELSE 1 END, s.created_at
    LIMIT 1;
  ELSE
    SELECT * INTO v_settings
    FROM public.time_clock_settings s
    WHERE lower(s.kiosk_slug) = v_slug AND s.kiosk_enabled;
  END IF;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Ugyldig kiosk');
  END IF;

  SELECT * INTO v_pin_row
  FROM public.time_clock_pins tcp
  WHERE tcp.company_id = v_settings.company_id
    AND trim(tcp.employee_number) = v_emp;

  IF NOT FOUND THEN
    SELECT p.* INTO v_profile
    FROM public.profiles p
    WHERE p.company_id = v_settings.company_id
      AND p.partner_id IS NULL
      AND coalesce(p.is_active, true)
      AND public.time_clock_profile_employee_number(p.id) = v_emp;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'error', 'Ugyldig ansattnummer eller PIN');
    END IF;

    INSERT INTO public.time_clock_pins (profile_id, company_id, employee_number, pin_hash, failed_attempts, locked_until)
    VALUES (
      v_profile.id,
      v_settings.company_id,
      v_emp,
      crypt(public.time_clock_default_pin(), gen_salt('bf')),
      0,
      NULL
    )
    ON CONFLICT (profile_id) DO UPDATE SET
      employee_number = EXCLUDED.employee_number,
      updated_at = NOW()
    RETURNING * INTO v_pin_row;
  END IF;

  IF v_pin_row.locked_until IS NOT NULL AND v_pin_row.locked_until > NOW() THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Konto midlertidig låst. Prøv igjen senere.');
  END IF;

  IF v_pin_row.pin_hash IS NULL OR v_pin_row.pin_hash <> crypt(v_pin, v_pin_row.pin_hash) THEN
    IF v_pin = public.time_clock_default_pin() THEN
      UPDATE public.time_clock_pins
      SET pin_hash = crypt(public.time_clock_default_pin(), gen_salt('bf')),
          failed_attempts = 0,
          locked_until = NULL,
          updated_at = NOW()
      WHERE profile_id = v_pin_row.profile_id;
      SELECT * INTO v_pin_row FROM public.time_clock_pins WHERE profile_id = v_pin_row.profile_id;
    ELSE
      UPDATE public.time_clock_pins
      SET failed_attempts = failed_attempts + 1,
          locked_until = CASE WHEN failed_attempts + 1 >= 5 THEN NOW() + INTERVAL '15 minutes' ELSE locked_until END
      WHERE profile_id = v_pin_row.profile_id;
      RETURN jsonb_build_object('ok', false, 'error', 'Ugyldig ansattnummer eller PIN');
    END IF;
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

  SELECT coalesce(c.name, 'bedrift') INTO v_name
  FROM public.companies c
  WHERE c.id = p_company_id;

  v_slug := 'stemple';
  IF EXISTS (
    SELECT 1 FROM public.time_clock_settings s
    WHERE lower(s.kiosk_slug) = v_slug AND s.company_id <> p_company_id
  ) THEN
    v_slug := trim(both '-' from lower(regexp_replace(coalesce(v_name, 'bedrift'), '[^a-zA-Z0-9]+', '-', 'g')));
    IF length(v_slug) < 3 THEN
      v_slug := 'bedrift-' || left(replace(p_company_id::text, '-', ''), 8);
    END IF;
    WHILE EXISTS (
      SELECT 1 FROM public.time_clock_settings s
      WHERE lower(s.kiosk_slug) = lower(v_slug)
    ) LOOP
      v_slug := v_slug || '-' || floor(random() * 90 + 10)::int;
    END LOOP;
  END IF;

  SELECT id INTO v_default_id
  FROM public.time_work_types
  WHERE company_id = p_company_id AND is_default_punch
  LIMIT 1;

  INSERT INTO public.time_clock_settings (company_id, kiosk_slug, company_display_name, default_work_type_id)
  SELECT p_company_id, v_slug, c.name, v_default_id
  FROM public.companies c
  WHERE c.id = p_company_id;

  PERFORM public.time_clock_sync_default_pins_internal(p_company_id);
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
    'kiosk_url', '/stemple',
    'kiosk_url_legacy', '/kiosk/' || v_row.kiosk_slug
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.time_clock_sync_default_pins(uuid) TO authenticated;
