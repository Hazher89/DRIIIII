-- MAVI interne ansatte: innlogging med ansattnummer + avdelinger fra Excel.

CREATE TABLE IF NOT EXISTS public.employee_login_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  employee_number TEXT NOT NULL,
  login_email TEXT NOT NULL,
  profile_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  address_line TEXT,
  postal_code TEXT,
  city TEXT,
  phone TEXT,
  department_slug TEXT NOT NULL,
  department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  must_change_password BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, employee_number),
  UNIQUE (login_email)
);

CREATE INDEX IF NOT EXISTS idx_employee_login_accounts_profile
  ON public.employee_login_accounts(profile_id);

ALTER TABLE public.employee_login_accounts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS employee_login_accounts_select_internal ON public.employee_login_accounts;
CREATE POLICY employee_login_accounts_select_internal ON public.employee_login_accounts
  FOR SELECT TO authenticated
  USING (
    company_id IN (SELECT p.company_id FROM public.profiles p WHERE p.id = auth.uid())
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x
      WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  );

CREATE OR REPLACE FUNCTION public.resolve_employee_login_email(p_employee_number TEXT)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT ela.login_email
  FROM public.employee_login_accounts ela
  WHERE ela.is_active = TRUE
    AND trim(ela.employee_number) = trim(p_employee_number)
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_employee_login_email(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.notify_employee_password_sms(
  p_company_id UUID,
  p_phone TEXT,
  p_employee_number TEXT,
  p_password TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO public.sms_outbox (
    company_id,
    to_phone,
    message,
    category,
    reference_type,
    reference_id
  )
  VALUES (
    p_company_id,
    p_phone,
    format(
      'MAVI DriftPro: nytt passord for ansatt %s er %s. Logg inn og endre passord under Profil ved behov. Mvh MAVI Logistikk',
      p_employee_number,
      p_password
    ),
    'employee_password',
    'employee_login_accounts',
    NULL
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_employee_password_sms(UUID, TEXT, TEXT, TEXT)
  TO authenticated, service_role;

-- Oppdater handle_new_user for ansatt-provisjon fra Edge Function.
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
BEGIN
  is_superadmin_account := lower(coalesce(new.email, '')) IN (
    'baxigshti@gmail.com',
    'baxightsi@gmail.com',
    'baxigshti@hotmail.de',
    'baxlgshtl@gmail.com'
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
        '{"hms": true, "fravaer": true, "avvik": true, "avdelinger": true, "ansatte": true}'::jsonb,
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
    '{}'::jsonb,
    CASE WHEN is_superadmin_account THEN TRUE ELSE FALSE END,
    CASE WHEN is_superadmin_account THEN TRUE ELSE FALSE END,
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

-- Avdelinger + katalog (uten auth-brukere — kjør Edge Function mavi-employees-import etterpå).
DO $$
DECLARE
  cid UUID;
  dept_admin UUID;
  dept_bilpark UUID;
  dept_lager UUID;
  dept_drift UUID;
  dept_rute UUID;
BEGIN
  SELECT id INTO cid FROM public.companies ORDER BY created_at LIMIT 1;
  IF cid IS NULL THEN
    RAISE NOTICE 'Ingen company — hopper over ansatt-import';
    RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.departments WHERE company_id = cid AND name = 'Administrasjon') THEN
    INSERT INTO public.departments (company_id, name, description, color_code, icon_name)
    VALUES (cid, 'Administrasjon', 'MAVI administrasjon', '#1565C0', 'admin_panel_settings');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.departments WHERE company_id = cid AND name = 'Bilpark') THEN
    INSERT INTO public.departments (company_id, name, description, color_code, icon_name)
    VALUES (cid, 'Bilpark', 'MAVI bilpark', '#2E7D32', 'local_shipping');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.departments WHERE company_id = cid AND name = 'Lager') THEN
    INSERT INTO public.departments (company_id, name, description, color_code, icon_name)
    VALUES (cid, 'Lager', 'MAVI lager', '#F57C00', 'inventory_2');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.departments WHERE company_id = cid AND name = 'Drift') THEN
    INSERT INTO public.departments (company_id, name, description, color_code, icon_name)
    VALUES (cid, 'Drift', 'MAVI drift', '#6A1B9A', 'engineering');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.departments WHERE company_id = cid AND name = 'Ruteplanlegger') THEN
    INSERT INTO public.departments (company_id, name, description, color_code, icon_name)
    VALUES (cid, 'Ruteplanlegger', 'MAVI ruteplanlegging', '#00838F', 'route');
  END IF;

  SELECT id INTO dept_admin FROM public.departments WHERE company_id = cid AND name = 'Administrasjon' LIMIT 1;
  SELECT id INTO dept_bilpark FROM public.departments WHERE company_id = cid AND name = 'Bilpark' LIMIT 1;
  SELECT id INTO dept_lager FROM public.departments WHERE company_id = cid AND name = 'Lager' LIMIT 1;
  SELECT id INTO dept_drift FROM public.departments WHERE company_id = cid AND name = 'Drift' LIMIT 1;
  SELECT id INTO dept_rute FROM public.departments WHERE company_id = cid AND name = 'Ruteplanlegger' LIMIT 1;

  INSERT INTO public.employee_login_accounts (
    company_id, employee_number, login_email, first_name, last_name,
    address_line, postal_code, city, phone, department_slug, department_id
  ) VALUES
    (cid, '144', 'e144@mavi-employees.driftpro.no', 'Nicola', 'Vino', 'Kløverbakken 13', '1940', 'Bjørkelangen', '40175011', 'administrasjon', dept_admin),
    (cid, '100', 'e100@mavi-employees.driftpro.no', 'Tommy', 'Larsen', 'Prost Stabels vei 325', '2019', 'Skedsmokorset', '40300519', 'administrasjon', dept_admin),
    (cid, '107', 'e107@mavi-employees.driftpro.no', 'Rafal', 'Dopieralski', 'Jordstjerneveien 52J', '1283', 'Oslo', '40075645', 'bilpark', dept_bilpark),
    (cid, '23', 'e23@mavi-employees.driftpro.no', 'Karwan', 'Lian', 'vårstigen 10', '1463', 'fjellhammer', '46671169', 'lager', dept_lager),
    (cid, '152', 'e152@mavi-employees.driftpro.no', 'Aware', 'Rasoulpour', 'Strømsveien 55', '2010', 'STRØMMEN', '40887282', 'lager', dept_lager),
    (cid, '200', 'e200@mavi-employees.driftpro.no', 'Hatam', 'Rasoulpour', 'Strømsveien 55', '2010', 'STRØMMEN', '40887282', 'lager', dept_lager),
    (cid, '103', 'e103@mavi-employees.driftpro.no', 'Madyar', 'Khezernia', 'Spellmannsplassen 10', '2008', 'Fjerdingby', '40094570', 'lager', dept_lager),
    (cid, '154', 'e154@mavi-employees.driftpro.no', 'Julie Sayeeda', 'Eyland Pande-Rolfsen', 'Heer Terrasse 34 F', '1445', 'DRØBAK', '96907180', 'drift', dept_drift),
    (cid, '113', 'e113@mavi-employees.driftpro.no', 'Herish', 'Hameed Alsabaawi', 'Prost Stabels vei 416', '2019', 'Skedsmokorset', '41619727', 'drift', dept_drift),
    (cid, '18', 'e18@mavi-employees.driftpro.no', 'Jaspreet', 'Singh', 'Toppen 13', '1470', 'Lørenskog', '95451389', 'drift', dept_drift),
    (cid, '125', 'e125@mavi-employees.driftpro.no', 'Adam', 'Michta', 'Hellaveien 41', '2013', 'Skjetten', '96802615', 'bilpark', dept_bilpark),
    (cid, '114', 'e114@mavi-employees.driftpro.no', 'Ingrid', 'Hoem', 'Øvre Nygård 12 b', '1482', 'NITTEDAL', '41263696', 'drift', dept_drift),
    (cid, '128', 'e128@mavi-employees.driftpro.no', 'Jamal', 'Farkhapour', 'Astrids vei 15', '1473', 'LØRENSKOG', '40583820', 'lager', dept_lager),
    (cid, '140', 'e140@mavi-employees.driftpro.no', 'Zelimhan Zavalovitsj', 'Magomedhadsjijev', 'Trygves vei 4', '1473', 'Lørenskog', '94833990', 'ruteplanlegger', dept_rute),
    (cid, '25', 'e25@mavi-employees.driftpro.no', 'Hazher', 'Abdullah Osman', 'Fredensborgveien 41b', '0177', 'Oslo', '45045451', 'administrasjon', dept_admin),
    (cid, '117', 'e117@mavi-employees.driftpro.no', 'Aso', 'Ibrahimi', 'Romsås senter 8', '0970', 'Oslo', '96747339', 'lager', dept_lager)
  ON CONFLICT (company_id, employee_number) DO UPDATE SET
    login_email = EXCLUDED.login_email,
    first_name = EXCLUDED.first_name,
    last_name = EXCLUDED.last_name,
    address_line = EXCLUDED.address_line,
    postal_code = EXCLUDED.postal_code,
    city = EXCLUDED.city,
    phone = EXCLUDED.phone,
    department_slug = EXCLUDED.department_slug,
    department_id = EXCLUDED.department_id,
    updated_at = NOW();
END $$;
