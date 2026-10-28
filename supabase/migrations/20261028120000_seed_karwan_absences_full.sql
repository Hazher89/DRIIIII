-- Full historikk for Karwan (ansattnr 23) fra Ansattfravær Excel/SAP.
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
  WHERE employee_number = '23'
     OR full_name ILIKE '%Karwan%'
  ORDER BY CASE WHEN employee_number = '23' THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke ansatt Karwan (23)';
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
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-01-13', '2022-01-21', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2022-03-18', '2022-03-18', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 161 egenmelding barns sykdom', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2022-03-31', '2022-04-01', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 161 egenmelding barns sykdom', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-05-04', '2022-05-06', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 160 egenmelding · tilfelle 1', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-07-25', '2022-07-25', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 160 egenmelding · tilfelle 2', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2022-08-29', '2022-08-29', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 161 egenmelding barns sykdom', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2022-10-07', '2022-10-07', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 161 egenmelding barns sykdom', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-10-31', '2022-11-02', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 160 egenmelding · tilfelle 3', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-12-20', '2022-12-22', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 160 egenmelding · tilfelle 4', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2023-01-23', '2023-01-23', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 161 egenmelding barns sykdom', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-01-31', '2023-02-03', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 160 egenmelding · tilfelle 5', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-02-06', '2023-02-08', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-02-24', '2023-02-24', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2023-06-20', '2023-06-22', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 161 egenmelding barns sykdom', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2023-09-14', '2023-09-15', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 161 egenmelding barns sykdom', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2023-10-02', '2023-10-02', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 161 egenmelding barns sykdom', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-11-02', '2023-11-03', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 160 egenmelding · tilfelle 6', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-12-19', '2023-12-19', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 160 egenmelding · tilfelle 7', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2024-01-02', '2024-01-03', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 161 egenmelding barns sykdom', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2024-04-17', '2024-04-19', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 161 egenmelding barns sykdom', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-05-27', '2024-05-29', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 160 egenmelding · tilfelle 8', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-08-08', '2024-08-08', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 160 egenmelding · tilfelle 9', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-10-02', '2024-10-04', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 160 egenmelding · tilfelle 10', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-11-15', '2024-11-15', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 160 egenmelding · tilfelle 11', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-01-02', '2025-01-03', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 160 egenmelding · tilfelle 12', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-02-17', '2025-02-21', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-02-24', '2025-02-28', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-03-06', '2025-03-06', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-04-08', '2025-04-09', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-06-23', '2025-06-24', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-08-04', '2025-08-06', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-08-26', '2025-08-29', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-10-20', '2025-10-20', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 160 egenmelding · tilfelle 13', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-01-16', '2026-01-16', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-01-28', '2026-01-30', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-02-03', '2026-02-06', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-02-18', '2026-02-23', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-02-27', '2026-02-27', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 160 egenmelding · tilfelle 1', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-03-02', '2026-03-20', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-05-12', '2026-05-13', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-05-20', '2026-05-22', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 160 egenmelding · tilfelle 2', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-06-19', '2026-06-19', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 160 egenmelding · tilfelle 3', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-06-22', '2026-06-23', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 160 egenmelding · tilfelle 4', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-08-24', '2026-08-28', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-09-24', '2026-09-25', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-09-28', '2026-10-26', 'godkjent', 'SAP/Excel · Ansattfravær Karwan · 170 sykmelding (under 16 dg)', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
