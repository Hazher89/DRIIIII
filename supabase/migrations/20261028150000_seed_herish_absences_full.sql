-- Full historikk for Herish (ansattnr 113) fra Ansattfravær Excel/SAP.
-- 175 «over 16 dg» er omgjort til 170 «under 16 dg» / sykmelding.
-- Erstatter tidligere delvis import.

DO $$
DECLARE
  v_user_id uuid;
  v_company_id uuid;
  v_dept_id uuid;
BEGIN
  SELECT id, company_id, department_id
  INTO v_user_id, v_company_id, v_dept_id
  FROM public.profiles
  WHERE employee_number = '113'
     OR full_name ILIKE '%Herish%'
  ORDER BY CASE WHEN employee_number = '113' THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke ansatt Herish (113)';
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
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2021-11-04', '2021-11-04', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 160 egenmelding · tilfelle 1', 2021),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2021-11-05', '2021-11-09', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2021),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2021-12-27', '2021-12-30', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2021),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2022-01-25', '2022-01-27', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-02-02', '2022-02-03', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 160 egenmelding · tilfelle 2', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2022-02-04', '2022-02-04', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-03-02', '2022-03-04', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 160 egenmelding · tilfelle 3', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-04-26', '2022-04-29', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2022-05-27', '2022-05-27', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-07-04', '2022-07-08', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2022-10-07', '2022-10-07', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2022-10-12', '2022-10-14', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-12-05', '2022-12-05', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 160 egenmelding · tilfelle 4', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2022-12-12', '2022-12-13', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-12-20', '2022-12-21', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-01-05', '2023-01-13', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2023-02-15', '2023-02-15', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-03-07', '2023-03-09', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 160 egenmelding · tilfelle 5', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2023-04-28', '2023-04-28', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-05-04', '2023-05-04', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 160 egenmelding · tilfelle 6', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2023-05-08', '2023-05-08', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2023-05-30', '2023-06-01', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-06-19', '2023-06-19', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 160 egenmelding · tilfelle 7', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2023-08-07', '2023-08-09', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-09-04', '2023-09-08', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2023-09-21', '2023-09-21', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-01-22', '2024-01-26', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2024-02-23', '2024-02-26', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-03-12', '2024-03-22', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2024-04-10', '2024-04-10', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-04-18', '2024-04-26', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-05-13', '2024-05-15', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 160 egenmelding · tilfelle 8', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2024-05-29', '2024-05-31', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-06-24', '2024-06-26', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 160 egenmelding · tilfelle 9', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2024-07-19', '2024-07-19', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-07-22', '2024-07-24', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 160 egenmelding · tilfelle 10', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-07-29', '2024-07-31', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2024-10-09', '2024-10-09', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-10-10', '2024-10-11', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-10-21', '2024-10-25', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2024-11-07', '2024-11-07', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2024-11-18', '2024-11-21', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-11-27', '2024-12-11', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-01-14', '2025-01-14', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-01-20', '2025-01-21', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 160 egenmelding · tilfelle 11', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-02-03', '2025-02-07', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-03-06', '2025-03-10', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-03-14', '2025-03-14', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-03-25', '2025-03-25', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-04-22', '2025-04-25', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-05-26', '2025-05-28', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 160 egenmelding · tilfelle 12', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-06-06', '2025-06-06', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-06-16', '2025-06-20', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-06-30', '2025-06-30', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-07-21', '2025-07-21', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-07-28', '2025-08-01', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-09-11', '2025-09-12', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-09-19', '2025-09-19', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-09-24', '2025-10-09', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-11-17', '2025-11-17', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 160 egenmelding · tilfelle 1', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-11-27', '2025-11-28', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 160 egenmelding · tilfelle 2', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-12-01', '2025-12-24', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-01-12', '2026-01-12', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-02-09', '2026-02-09', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 160 egenmelding · tilfelle 3', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-02-16', '2026-02-18', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-03-09', '2026-03-09', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 160 egenmelding · tilfelle 4', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-03-16', '2026-03-16', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-04-09', '2026-04-10', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-04-16', '2026-04-17', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-05-07', '2026-05-07', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-05-18', '2026-05-22', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-05-29', '2026-06-01', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-09-09', '2026-09-11', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-09-28', '2026-10-01', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-10-14', '2026-10-23', 'godkjent', 'SAP/Excel · Ansattfravær Herish · 170 sykmelding (under 16 dg)', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
