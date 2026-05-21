-- Flytt MAVI Excel-ansatte til samme selskap som superadmin (bootstrap).
-- De ble opprettet på eldste company_id; appen filtrerer på innlogget brukers company_id.

DO $$
DECLARE
  target_company UUID := '00000000-0000-0000-0000-000000000000';
  dept_admin UUID;
  dept_bilpark UUID;
  dept_lager UUID;
  dept_drift UUID;
  dept_rute UUID;
BEGIN
  SELECT id INTO dept_admin
  FROM public.departments
  WHERE company_id = target_company AND name ILIKE 'Administrasjon%'
  ORDER BY name
  LIMIT 1;

  SELECT id INTO dept_bilpark
  FROM public.departments
  WHERE company_id = target_company AND name ILIKE 'Bilpark%'
  LIMIT 1;

  SELECT id INTO dept_lager
  FROM public.departments
  WHERE company_id = target_company AND name ILIKE 'Lager%'
  LIMIT 1;

  SELECT id INTO dept_drift
  FROM public.departments
  WHERE company_id = target_company AND name ILIKE 'Drift%'
  LIMIT 1;

  SELECT id INTO dept_rute
  FROM public.departments
  WHERE company_id = target_company AND name ILIKE 'Ruteplanlegger%'
  LIMIT 1;

  UPDATE public.employee_login_accounts ela
  SET
    company_id = target_company,
    department_id = CASE ela.department_slug
      WHEN 'administrasjon' THEN dept_admin
      WHEN 'bilpark' THEN dept_bilpark
      WHEN 'lager' THEN dept_lager
      WHEN 'drift' THEN dept_drift
      WHEN 'ruteplanlegger' THEN dept_rute
      ELSE ela.department_id
    END,
    updated_at = NOW()
  WHERE ela.login_email LIKE '%@mavi-employees.driftpro.no';

  UPDATE public.profiles p
  SET
    company_id = target_company,
    department_id = CASE ela.department_slug
      WHEN 'administrasjon' THEN dept_admin
      WHEN 'bilpark' THEN dept_bilpark
      WHEN 'lager' THEN dept_lager
      WHEN 'drift' THEN dept_drift
      WHEN 'ruteplanlegger' THEN dept_rute
      ELSE p.department_id
    END
  FROM public.employee_login_accounts ela
  WHERE ela.profile_id = p.id
    AND ela.login_email LIKE '%@mavi-employees.driftpro.no';
END $$;
