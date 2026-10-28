-- Full historikk for Madyar (ansattnr 103) fra Ansattfravær Excel/SAP.
-- 175 «over 16 dg» er omgjort til 170 «under 16 dg» / sykmelding.

DO $$
DECLARE
  v_user_id uuid;
  v_company_id uuid;
  v_dept_id uuid;
BEGIN
  SELECT id, company_id, department_id
  INTO v_user_id, v_company_id, v_dept_id
  FROM public.profiles
  WHERE employee_number = '103'
     OR full_name ILIKE '%Madyar%'
  ORDER BY CASE WHEN employee_number = '103' THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke ansatt Madyar (103)';
  END IF;

  ALTER TABLE public.absences DISABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences DISABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences DISABLE TRIGGER validate_ferie_quota_trigger;

  DELETE FROM public.absences
  WHERE user_id = v_user_id
    AND (
      comment LIKE 'Importert historikk (SAP/Excel)%'
      OR comment LIKE 'SAP/Excel%'
    );

  INSERT INTO public.absences (
    user_id, company_id, department_id, type, start_date, end_date, status, comment, quota_year
  ) VALUES
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-03-11', '2022-03-11', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 160 egenmelding · tilfelle 1', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-03-14', '2022-03-18', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-04-01', '2022-04-01', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 160 egenmelding · tilfelle 2', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2022-06-23', '2022-06-23', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 161 egenmelding barns sykdom', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2022-09-12', '2022-09-12', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 161 egenmelding barns sykdom', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-02-08', '2023-02-10', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 160 egenmelding · tilfelle 3', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2023-02-14', '2023-02-15', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 161 egenmelding barns sykdom', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2023-03-09', '2023-03-10', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 161 egenmelding barns sykdom', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2023-03-21', '2023-03-21', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 161 egenmelding barns sykdom', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-01-02', '2024-01-02', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 160 egenmelding · tilfelle 4', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-01-25', '2024-01-26', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 160 egenmelding · tilfelle 5', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-03-15', '2024-03-15', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 160 egenmelding · tilfelle 6', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-03-19', '2024-03-21', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 160 egenmelding · tilfelle 7', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2024-12-30', '2024-12-30', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 161 egenmelding barns sykdom', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-04-15', '2025-04-16', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-02-19', '2026-02-19', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-03-23', '2026-03-23', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-05-28', '2026-05-28', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-06-17', '2026-06-17', 'godkjent', 'SAP/Excel · Ansattfravær Madyar · 160 egenmelding · tilfelle 1', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
