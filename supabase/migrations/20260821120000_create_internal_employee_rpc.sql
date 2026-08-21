-- Opprett intern ansatt uten Edge Function (auth.users + profil + login-konto).
-- Bruker samme e-postdomene som MAVI-import: e{nr}@mavi-employees.driftpro.no

CREATE OR REPLACE FUNCTION public.resolve_employee_login_email(p_employee_number TEXT)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT coalesce(
    (
      SELECT ela.login_email
      FROM public.employee_login_accounts ela
      WHERE ela.is_active = TRUE
        AND trim(ela.employee_number) = trim(p_employee_number)
      LIMIT 1
    ),
    (
      SELECT p.email
      FROM public.profiles p
      WHERE p.is_active IS DISTINCT FROM FALSE
        AND p.partner_id IS NULL
        AND trim(coalesce(p.employee_number, '')) = trim(p_employee_number)
        AND coalesce(trim(p.email), '') <> ''
      LIMIT 1
    )
  );
$$;

GRANT EXECUTE ON FUNCTION public.resolve_employee_login_email(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_internal_employee(
  p_company_id uuid,
  p_full_name text,
  p_employee_number text,
  p_department_id uuid DEFAULT NULL,
  p_job_title text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_role text DEFAULT 'ansatt'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
  v_requester_id uuid := auth.uid();
  v_requester public.profiles%ROWTYPE;
  v_role text := lower(trim(coalesce(p_role, 'ansatt')));
  v_emp_no text := trim(coalesce(p_employee_number, ''));
  v_full_name text := trim(coalesce(p_full_name, ''));
  v_job_title text := nullif(trim(coalesce(p_job_title, '')), '');
  v_phone text := nullif(trim(coalesce(p_phone, '')), '');
  v_email text;
  v_uid uuid := gen_random_uuid();
  v_first text;
  v_last text;
  v_slug text := 'intern';
  v_profile public.profiles%ROWTYPE;
  v_default_password constant text := '000000';
BEGIN
  IF v_requester_id IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_requester
  FROM public.profiles
  WHERE id = v_requester_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fant ikke profil';
  END IF;

  IF v_requester.role::text NOT IN ('admin', 'superadmin', 'leder') THEN
    RAISE EXCEPTION 'Mangler tilgang';
  END IF;

  IF v_requester.role::text <> 'superadmin'
     AND v_requester.company_id IS DISTINCT FROM p_company_id THEN
    RAISE EXCEPTION 'Feil selskap';
  END IF;

  IF v_full_name = '' OR v_emp_no = '' OR p_company_id IS NULL THEN
    RAISE EXCEPTION 'Navn, ansattnummer og selskap er påkrevd';
  END IF;

  IF v_role NOT IN ('ansatt', 'leder', 'admin') THEN
    v_role := 'ansatt';
  END IF;

  IF v_requester.role::text = 'leder' THEN
    IF p_department_id IS NULL
       OR p_department_id IS DISTINCT FROM v_requester.department_id THEN
      RAISE EXCEPTION 'Leder kan kun legge til i egen avdeling';
    END IF;
    IF v_role IN ('admin', 'leder', 'superadmin') THEN
      RAISE EXCEPTION 'Leder kan kun opprette ansatte';
    END IF;
    v_role := 'ansatt';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.employee_login_accounts ela
    WHERE ela.company_id = p_company_id
      AND trim(ela.employee_number) = v_emp_no
  ) OR EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.company_id = p_company_id
      AND trim(coalesce(p.employee_number, '')) = v_emp_no
  ) THEN
    RAISE EXCEPTION 'Ansattnummer % er allerede i bruk', v_emp_no;
  END IF;

  v_email := lower('e' || v_emp_no || '@mavi-employees.driftpro.no');

  IF EXISTS (
    SELECT 1 FROM auth.users u WHERE lower(u.email) = v_email
  ) OR EXISTS (
    SELECT 1 FROM public.employee_login_accounts ela
    WHERE lower(ela.login_email) = v_email
  ) THEN
    RAISE EXCEPTION 'Innloggingskonto for ansattnummer % finnes allerede', v_emp_no;
  END IF;

  IF p_department_id IS NOT NULL THEN
    SELECT lower(regexp_replace(coalesce(d.name, 'intern'), '[^a-zA-Z0-9]+', '', 'g'))
    INTO v_slug
    FROM public.departments d
    WHERE d.id = p_department_id
      AND d.company_id = p_company_id;
    IF coalesce(v_slug, '') = '' THEN
      v_slug := 'intern';
    END IF;
  END IF;

  v_first := split_part(v_full_name, ' ', 1);
  v_last := nullif(trim(substr(v_full_name, length(v_first) + 1)), '');
  IF v_last IS NULL THEN
    v_last := v_first;
  END IF;

  INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    v_uid,
    'authenticated',
    'authenticated',
    v_email,
    extensions.crypt(v_default_password, extensions.gen_salt('bf')),
    now(),
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
    jsonb_build_object(
      'employee_provision', true,
      'company_id', p_company_id,
      'department_id', p_department_id,
      'employee_number', v_emp_no,
      'full_name', v_full_name,
      'job_title', v_job_title,
      'phone', v_phone,
      'internal_org_chart', true
    ),
    now(),
    now(),
    '',
    '',
    '',
    ''
  );

  INSERT INTO auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
  ) VALUES (
    v_uid,
    v_uid,
    jsonb_build_object(
      'sub', v_uid::text,
      'email', v_email,
      'email_verified', true,
      'phone_verified', false
    ),
    'email',
    v_uid::text,
    now(),
    now(),
    now()
  );

  INSERT INTO public.profiles (
    id,
    email,
    full_name,
    company_id,
    department_id,
    job_title,
    phone,
    employee_number,
    role,
    access_settings,
    is_onboarded,
    is_approved,
    is_active
  ) VALUES (
    v_uid,
    v_email,
    v_full_name,
    p_company_id,
    p_department_id,
    v_job_title,
    v_phone,
    v_emp_no,
    v_role::public.user_role,
    jsonb_build_object(
      'dashboard', true,
      'more', true,
      'fravaer', true,
      'avvik', true,
      'whistleblowing', true,
      'profil', true,
      'stempling', true,
      'hms', true,
      'avdelinger', true,
      'ansatte', true
    ),
    TRUE,
    TRUE,
    TRUE
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = EXCLUDED.full_name,
    company_id = EXCLUDED.company_id,
    department_id = EXCLUDED.department_id,
    job_title = EXCLUDED.job_title,
    phone = COALESCE(EXCLUDED.phone, public.profiles.phone),
    employee_number = EXCLUDED.employee_number,
    role = EXCLUDED.role,
    access_settings = EXCLUDED.access_settings,
    is_onboarded = TRUE,
    is_approved = TRUE,
    is_active = TRUE;

  INSERT INTO public.employee_login_accounts (
    company_id,
    employee_number,
    login_email,
    profile_id,
    first_name,
    last_name,
    phone,
    department_slug,
    department_id,
    is_active,
    must_change_password
  ) VALUES (
    p_company_id,
    v_emp_no,
    v_email,
    v_uid,
    v_first,
    v_last,
    v_phone,
    v_slug,
    p_department_id,
    TRUE,
    TRUE
  )
  ON CONFLICT (company_id, employee_number) DO UPDATE SET
    login_email = EXCLUDED.login_email,
    profile_id = EXCLUDED.profile_id,
    first_name = EXCLUDED.first_name,
    last_name = EXCLUDED.last_name,
    phone = COALESCE(EXCLUDED.phone, public.employee_login_accounts.phone),
    department_slug = EXCLUDED.department_slug,
    department_id = EXCLUDED.department_id,
    is_active = TRUE,
    must_change_password = TRUE,
    updated_at = now();

  BEGIN
    PERFORM public.ensure_absence_quota(v_uid, extract(year from now())::int);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  SELECT * INTO v_profile FROM public.profiles WHERE id = v_uid;

  RETURN jsonb_build_object(
    'ok', true,
    'profile', to_jsonb(v_profile),
    'default_password', v_default_password,
    'login_email', v_email,
    'employee_number', v_emp_no
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_internal_employee(uuid, text, text, uuid, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_internal_employee(uuid, text, text, uuid, text, text, text) TO authenticated;
