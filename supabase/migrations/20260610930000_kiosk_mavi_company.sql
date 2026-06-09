-- Kiosk skal alltid bruke MAVI Logistikk (ikke demo-selskap).

CREATE OR REPLACE FUNCTION public.get_kiosk_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.id
  FROM public.companies c
  WHERE c.id <> '00000000-0000-0000-0000-000000000000'::uuid
  ORDER BY
    CASE
      WHEN c.name ILIKE '%mavi%' THEN 0
      WHEN c.name ILIKE '%logistikk%' THEN 1
      ELSE 2
    END,
    (
      SELECT count(*)
      FROM public.profiles p
      WHERE p.company_id = c.id
        AND p.partner_id IS NULL
        AND coalesce(p.is_active, true)
    ) DESC,
    c.created_at
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.kiosk_find_profile_by_employee_number(
  p_company_id uuid,
  p_employee_number text
)
RETURNS public.profiles
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp text := trim(coalesce(p_employee_number, ''));
  v_row public.profiles%ROWTYPE;
BEGIN
  IF v_emp = '' THEN
    RETURN NULL;
  END IF;

  SELECT p.* INTO v_row
  FROM public.employee_login_accounts ela
  JOIN public.profiles p ON p.id = ela.profile_id
  WHERE ela.company_id = p_company_id
    AND ela.is_active
    AND trim(ela.employee_number) = v_emp
  LIMIT 1;

  IF FOUND THEN
    RETURN v_row;
  END IF;

  SELECT p.* INTO v_row
  FROM public.profiles p
  WHERE p.company_id = p_company_id
    AND p.partner_id IS NULL
    AND coalesce(p.is_active, true)
    AND trim(coalesce(nullif(trim(p.employee_number), ''), '')) = v_emp
  LIMIT 1;

  IF FOUND THEN
    RETURN v_row;
  END IF;

  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.kiosk_bootstrap_default_company()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_company_id uuid := public.get_kiosk_company_id();
BEGIN
  IF v_company_id IS NULL THEN
    RETURN NULL;
  END IF;

  PERFORM public.ensure_time_clock_company(v_company_id);

  UPDATE public.time_clock_settings s
  SET
    kiosk_enabled = TRUE,
    kiosk_slug = 'stemple',
    company_display_name = c.name,
    updated_at = NOW()
  FROM public.companies c
  WHERE s.company_id = v_company_id
    AND c.id = v_company_id;

  PERFORM public.time_clock_sync_default_pins_internal(v_company_id);
  RETURN v_company_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.kiosk_resolve_settings(p_slug text)
RETURNS public.time_clock_settings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row public.time_clock_settings%ROWTYPE;
  v_slug text := lower(trim(coalesce(p_slug, '')));
  v_company_id uuid := public.get_kiosk_company_id();
BEGIN
  IF v_company_id IS NOT NULL THEN
    PERFORM public.ensure_time_clock_company(v_company_id);

    SELECT * INTO v_row
    FROM public.time_clock_settings s
    WHERE s.company_id = v_company_id
    LIMIT 1;

    IF FOUND THEN
      UPDATE public.time_clock_settings s
      SET
        kiosk_enabled = TRUE,
        company_display_name = c.name,
        updated_at = NOW()
      FROM public.companies c
      WHERE s.company_id = v_company_id
        AND c.id = v_company_id
        AND (
          s.company_display_name IS DISTINCT FROM c.name
          OR NOT s.kiosk_enabled
        );

      SELECT * INTO v_row
      FROM public.time_clock_settings s
      WHERE s.company_id = v_company_id
      LIMIT 1;

      RETURN v_row;
    END IF;
  END IF;

  IF v_slug = '' OR v_slug = 'stemple' THEN
    SELECT * INTO v_row
    FROM public.time_clock_settings s
    WHERE s.kiosk_enabled = TRUE
      AND s.company_id <> '00000000-0000-0000-0000-000000000000'::uuid
    ORDER BY CASE WHEN lower(s.kiosk_slug) = 'stemple' THEN 0 ELSE 1 END, s.created_at
    LIMIT 1;
  ELSE
    SELECT * INTO v_row
    FROM public.time_clock_settings s
    WHERE lower(s.kiosk_slug) = v_slug
      AND s.kiosk_enabled = TRUE
      AND s.company_id <> '00000000-0000-0000-0000-000000000000'::uuid;
  END IF;

  IF NOT FOUND THEN
    PERFORM public.kiosk_bootstrap_default_company();
    SELECT * INTO v_row
    FROM public.time_clock_settings s
    WHERE s.company_id = public.get_kiosk_company_id()
    LIMIT 1;
  END IF;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.kiosk_get_company(p_slug text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_row public.time_clock_settings;
  v_name text;
BEGIN
  v_row := public.kiosk_resolve_settings(p_slug);

  IF v_row.company_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Kiosk er ikke satt opp ennå. Kontakt administrator.'
    );
  END IF;

  SELECT c.name INTO v_name FROM public.companies c WHERE c.id = v_row.company_id;

  RETURN jsonb_build_object(
    'ok', true,
    'company_id', v_row.company_id,
    'display_name', coalesce(v_name, v_row.company_display_name, v_row.kiosk_slug),
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
SET search_path = public, extensions
AS $$
DECLARE
  v_settings public.time_clock_settings;
  v_pin_row public.time_clock_pins%ROWTYPE;
  v_profile public.profiles%ROWTYPE;
  v_state public.time_clock_state%ROWTYPE;
  v_session_id uuid;
  v_default_type uuid;
  v_emp text := trim(coalesce(p_employee_number, ''));
  v_pin text := coalesce(nullif(trim(p_pin), ''), public.time_clock_default_pin());
BEGIN
  IF v_emp = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Angi ansattnummer');
  END IF;

  v_settings := public.kiosk_resolve_settings(p_slug);

  IF v_settings.company_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Kiosk er ikke satt opp ennå');
  END IF;

  SELECT * INTO v_pin_row
  FROM public.time_clock_pins tcp
  WHERE tcp.company_id = v_settings.company_id
    AND trim(tcp.employee_number) = v_emp;

  IF NOT FOUND THEN
    v_profile := public.kiosk_find_profile_by_employee_number(v_settings.company_id, v_emp);

    IF v_profile IS NULL OR v_profile.id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'Ugyldig ansattnummer eller PIN');
    END IF;

    INSERT INTO public.time_clock_pins (profile_id, company_id, employee_number, pin_hash, failed_attempts, locked_until)
    VALUES (
      v_profile.id,
      v_settings.company_id,
      v_emp,
      extensions.crypt(public.time_clock_default_pin(), extensions.gen_salt('bf')),
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

  IF v_pin_row.pin_hash IS NULL OR v_pin_row.pin_hash <> extensions.crypt(v_pin, v_pin_row.pin_hash) THEN
    IF v_pin = public.time_clock_default_pin() THEN
      UPDATE public.time_clock_pins
      SET pin_hash = extensions.crypt(public.time_clock_default_pin(), extensions.gen_salt('bf')),
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

-- Rydd demo-kiosk og pek alt til MAVI.
DELETE FROM public.time_clock_settings
WHERE company_id = '00000000-0000-0000-0000-000000000000'::uuid;

SELECT public.kiosk_bootstrap_default_company();

GRANT EXECUTE ON FUNCTION public.get_kiosk_company_id() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.kiosk_find_profile_by_employee_number(uuid, text) TO anon, authenticated;
