-- Full historikk for Jaspreet Singh (ansattnr 18) fra Ansattfravær Excel/SAP.
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
  WHERE employee_number = '18'
     OR full_name ILIKE '%Jaspreet%Singh%'
  ORDER BY CASE WHEN employee_number = '18' THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke ansatt Jaspreet (18)';
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
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2021-11-03', '2021-11-12', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 170 sykmelding (under 16 dg)', 2021),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2021-12-01', '2021-12-01', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2021),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2022-02-01', '2022-02-01', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-02-15', '2022-02-17', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 160 egenmelding · tilfelle 1', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2022-04-22', '2022-04-22', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-05-02', '2022-05-06', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-05-18', '2022-05-20', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 160 egenmelding · tilfelle 2', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2022-07-18', '2022-07-19', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-01-31', '2023-02-02', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 160 egenmelding · tilfelle 3', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2023-03-06', '2023-03-06', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-04-19', '2023-04-21', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 160 egenmelding · tilfelle 4', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2023-05-24', '2023-05-24', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2023-06-19', '2023-06-19', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-07-03', '2023-10-25', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2023-10-26', '2023-10-27', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-10-31', '2023-11-03', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-11-29', '2023-11-30', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 160 egenmelding · tilfelle 5', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2023-12-15', '2023-12-15', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2024-01-16', '2024-01-19', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2024-02-27', '2024-02-27', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-03-04', '2024-03-05', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 160 egenmelding · tilfelle 6', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2024-03-20', '2024-03-21', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-04-15', '2024-04-17', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 160 egenmelding · tilfelle 7', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-05-13', '2024-05-15', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2024-06-17', '2024-06-17', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-07-08', '2024-07-10', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 160 egenmelding · tilfelle 8', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-09-12', '2024-09-13', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-09-30', '2024-10-04', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2024-11-19', '2024-11-19', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-12-02', '2024-12-04', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 160 egenmelding · tilfelle 9', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-12-05', '2024-12-13', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-01-08', '2025-01-08', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-01-29', '2025-01-30', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-02-10', '2025-02-12', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-02-26', '2025-02-28', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-03-27', '2025-03-27', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-04-01', '2025-04-03', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 160 egenmelding · tilfelle 10', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-04-24', '2025-04-25', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-05-09', '2025-05-09', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-06-11', '2025-06-12', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-06-16', '2025-06-18', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 160 egenmelding · tilfelle 11', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-07-02', '2025-07-03', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-08-11', '2025-08-13', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 160 egenmelding · tilfelle 12', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-01-09', '2026-01-09', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-01-22', '2026-01-23', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 160 egenmelding · tilfelle 1', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-02-02', '2026-02-06', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-03-04', '2026-03-13', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-03-23', '2026-03-23', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-03-31', '2026-03-31', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-05-04', '2026-05-04', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-05-11', '2026-05-13', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 160 egenmelding · tilfelle 2', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-06-09', '2026-06-09', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-06-29', '2026-06-30', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 160 egenmelding · tilfelle 3', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-07-29', '2026-07-30', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-08-31', '2026-08-31', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-09-15', '2026-09-15', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-10-07', '2026-10-08', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-10-12', '2026-10-14', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 160 egenmelding · tilfelle 4', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-10-20', '2026-10-22', 'godkjent', 'SAP/Excel · Ansattfravær Jaspreet · 170 sykmelding (under 16 dg)', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
