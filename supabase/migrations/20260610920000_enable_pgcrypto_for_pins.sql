-- pgcrypto (crypt/gen_salt) ligger i extensions-schema på Supabase.
-- Tidligere funksjoner hadde search_path = public og fant ikke gen_salt.

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.time_clock_sync_default_pins_internal(p_company_id uuid)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_count int := 0;
BEGIN
  INSERT INTO public.time_clock_pins (profile_id, company_id, employee_number, pin_hash, failed_attempts, locked_until)
  SELECT
    p.id,
    p.company_id,
    public.time_clock_profile_employee_number(p.id),
    extensions.crypt(public.time_clock_default_pin(), extensions.gen_salt('bf')),
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
    pin_hash = extensions.crypt(public.time_clock_default_pin(), extensions.gen_salt('bf')),
    failed_attempts = 0,
    locked_until = NULL,
    updated_at = NOW();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.time_clock_set_pin(
  p_profile_id uuid,
  p_pin text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
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
  VALUES (p_profile_id, v_company_id, v_emp_no, extensions.crypt(p_pin, extensions.gen_salt('bf')), 0, NULL)
  ON CONFLICT (profile_id) DO UPDATE SET
    employee_number = EXCLUDED.employee_number,
    pin_hash = EXCLUDED.pin_hash,
    failed_attempts = 0,
    locked_until = NULL,
    updated_at = NOW();
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

-- Synk alle eksisterende ansatte til PIN 0 etter fiks.
SELECT public.time_clock_sync_default_pins_internal(c.id)
FROM public.companies c;
