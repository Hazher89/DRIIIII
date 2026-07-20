-- OAuth (Google/Apple) self-signup: auto-godkjenn med standard ansatt-tilgang.
-- Bevarer portal_provision og employee_provision-stiene.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  default_company_id UUID;
  is_superadmin_account BOOLEAN;
  portal_provision BOOLEAN;
  employee_provision BOOLEAN;
  meta_company_id UUID;
  meta_partner_id UUID;
  meta_vehicle_id UUID;
  meta_phone TEXT;
  meta_department_id UUID;
  meta_employee_number TEXT;
  meta_full_name TEXT;
  meta_address TEXT;
  employee_access JSONB := jsonb_build_object(
    'dashboard', true,
    'more', true,
    'fravaer', true,
    'avvik', true,
    'whistleblowing', true,
    'profil', true,
    'stempling', true
  );
BEGIN
  is_superadmin_account := lower(coalesce(new.email, '')) IN (
    'baxigshti@gmail.com',
    'baxightsi@gmail.com',
    'baxigshti@hotmail.de',
    'baxlgshtl@gmail.com',
    'hazher@mavilogistikk.no'
  );

  portal_provision :=
    COALESCE(new.raw_user_meta_data->>'portal_provision', '') IN ('true', '1', 'yes');
  employee_provision :=
    COALESCE(new.raw_user_meta_data->>'employee_provision', '') IN ('true', '1', 'yes');

  IF portal_provision
     AND trim(COALESCE(new.raw_user_meta_data->>'company_id', '')) <> '' THEN
    BEGIN
      meta_company_id := (new.raw_user_meta_data->>'company_id')::uuid;
    EXCEPTION
      WHEN invalid_text_representation THEN
        meta_company_id := NULL;
    END;

    IF trim(COALESCE(new.raw_user_meta_data->>'partner_id', '')) <> '' THEN
      BEGIN
        meta_partner_id := (new.raw_user_meta_data->>'partner_id')::uuid;
      EXCEPTION
        WHEN invalid_text_representation THEN
          meta_partner_id := NULL;
      END;
    END IF;

    meta_vehicle_id := NULL;
    IF trim(COALESCE(new.raw_user_meta_data->>'partner_vehicle_id', '')) <> '' THEN
      BEGIN
        meta_vehicle_id := (new.raw_user_meta_data->>'partner_vehicle_id')::uuid;
      EXCEPTION
        WHEN invalid_text_representation THEN
          meta_vehicle_id := NULL;
      END;
    END IF;

    meta_phone := nullif(trim(new.raw_user_meta_data->>'phone'), '');

    IF meta_company_id IS NOT NULL THEN
      INSERT INTO public.profiles (
        id, email, full_name, company_id, role, access_settings,
        is_onboarded, is_approved, is_active, partner_id, partner_vehicle_id, phone
      )
      VALUES (
        new.id,
        new.email,
        COALESCE(
          new.raw_user_meta_data->>'full_name',
          new.raw_user_meta_data->>'name',
          split_part(coalesce(new.email, 'portal'), '@', 1)
        ),
        meta_company_id,
        'samarbeidspartner'::public.user_role,
        '{}'::jsonb,
        TRUE,
        TRUE,
        TRUE,
        meta_partner_id,
        meta_vehicle_id,
        meta_phone
      )
      ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        full_name = COALESCE(public.profiles.full_name, EXCLUDED.full_name),
        company_id = EXCLUDED.company_id,
        partner_id = EXCLUDED.partner_id,
        partner_vehicle_id = EXCLUDED.partner_vehicle_id,
        phone = COALESCE(EXCLUDED.phone, public.profiles.phone),
        role = 'samarbeidspartner'::public.user_role,
        is_onboarded = TRUE,
        is_approved = TRUE,
        is_active = TRUE;
      RETURN new;
    END IF;
  END IF;

  IF employee_provision
     AND trim(COALESCE(new.raw_user_meta_data->>'company_id', '')) <> '' THEN
    BEGIN
      meta_company_id := (new.raw_user_meta_data->>'company_id')::uuid;
    EXCEPTION
      WHEN invalid_text_representation THEN
        meta_company_id := NULL;
    END;

    meta_department_id := NULL;
    IF trim(COALESCE(new.raw_user_meta_data->>'department_id', '')) <> '' THEN
      BEGIN
        meta_department_id := (new.raw_user_meta_data->>'department_id')::uuid;
      EXCEPTION
        WHEN invalid_text_representation THEN
          meta_department_id := NULL;
      END;
    END IF;

    meta_phone := nullif(trim(new.raw_user_meta_data->>'phone'), '');
    meta_employee_number := nullif(trim(new.raw_user_meta_data->>'employee_number'), '');
    meta_full_name := nullif(trim(new.raw_user_meta_data->>'full_name'), '');
    meta_address := nullif(trim(new.raw_user_meta_data->>'address'), '');

    IF meta_company_id IS NOT NULL THEN
      INSERT INTO public.profiles (
        id, email, full_name, company_id, role, access_settings,
        is_onboarded, is_approved, is_active, phone, employee_number,
        department_id, address
      )
      VALUES (
        new.id,
        new.email,
        COALESCE(meta_full_name, 'MAVI ansatt'),
        meta_company_id,
        'ansatt'::public.user_role,
        employee_access,
        TRUE,
        TRUE,
        TRUE,
        meta_phone,
        meta_employee_number,
        meta_department_id,
        meta_address
      )
      ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
        company_id = EXCLUDED.company_id,
        phone = COALESCE(EXCLUDED.phone, public.profiles.phone),
        employee_number = COALESCE(EXCLUDED.employee_number, public.profiles.employee_number),
        department_id = COALESCE(EXCLUDED.department_id, public.profiles.department_id),
        address = COALESCE(EXCLUDED.address, public.profiles.address),
        is_onboarded = TRUE,
        is_approved = TRUE,
        is_active = TRUE,
        role = 'ansatt'::public.user_role;

      IF meta_employee_number IS NOT NULL THEN
        UPDATE public.employee_login_accounts
        SET profile_id = new.id, updated_at = NOW()
        WHERE company_id = meta_company_id
          AND employee_number = meta_employee_number;
      END IF;

      RETURN new;
    END IF;
  END IF;

  SELECT id INTO default_company_id FROM public.companies LIMIT 1;

  -- Google/Apple (og øvrig selvregistrering): godkjent ansatt med ren tilgang.
  INSERT INTO public.profiles (
    id, email, full_name, company_id, role, access_settings,
    is_onboarded, is_approved, is_active
  )
  VALUES (
    new.id,
    new.email,
    COALESCE(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      'Ny bruker'
    ),
    default_company_id,
    CASE
      WHEN is_superadmin_account THEN 'superadmin'::public.user_role
      ELSE 'ansatt'::public.user_role
    END,
    CASE
      WHEN is_superadmin_account THEN '{}'::jsonb
      ELSE employee_access
    END,
    CASE WHEN is_superadmin_account THEN TRUE ELSE FALSE END,
    TRUE,
    TRUE
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = COALESCE(public.profiles.full_name, EXCLUDED.full_name);

  RETURN new;
EXCEPTION WHEN OTHERS THEN
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Eksisterende OAuth-brukere som står i «venter på godkjenning» uten ansattnummer:
-- gi dem samme rene ansatt-opplevelse (ikke rør partnere / MAVI-ansattnummer).
UPDATE public.profiles p
SET
  is_approved = TRUE,
  is_active = TRUE,
  role = 'ansatt'::public.user_role,
  access_settings = jsonb_build_object(
    'dashboard', true,
    'more', true,
    'fravaer', true,
    'avvik', true,
    'whistleblowing', true,
    'profil', true,
    'stempling', true
  )
WHERE p.role = 'ansatt'::public.user_role
  AND p.is_approved = FALSE
  AND coalesce(nullif(trim(p.employee_number), ''), '') = ''
  AND p.partner_id IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.employee_login_accounts ela
    WHERE ela.profile_id = p.id OR lower(trim(ela.login_email)) = lower(trim(p.email))
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.partner_portal_accounts ppa
    WHERE ppa.profile_id = p.id OR lower(trim(ppa.login_email)) = lower(trim(p.email))
  );
