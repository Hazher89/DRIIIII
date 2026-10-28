-- Full historikk for Ingrid (ansattnr 114) fra Ansattfravær Excel/SAP.
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
  WHERE employee_number = '114'
     OR full_name ILIKE '%Ingrid%'
  ORDER BY CASE WHEN employee_number = '114' THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke ansatt Ingrid (114)';
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
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2021-11-18', '2021-11-22', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2021),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-01-10', '2022-01-14', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-02-17', '2022-02-17', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 160 egenmelding · tilfelle 1', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-02-28', '2022-03-04', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-03-09', '2022-03-18', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-09-08', '2022-09-08', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 160 egenmelding · tilfelle 2', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-09-13', '2022-09-16', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-09-28', '2022-10-03', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 160 egenmelding · tilfelle 3', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-11-02', '2022-11-02', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 160 egenmelding · tilfelle 4', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-11-07', '2022-11-08', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-11-15', '2022-11-28', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-12-07', '2022-12-07', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-12-20', '2022-12-20', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-01-03', '2023-01-05', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-01-11', '2023-01-13', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-01-17', '2023-01-18', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-01-23', '2023-01-26', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-02-01', '2023-02-03', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-02-07', '2023-02-15', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-02-21', '2023-03-15', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-03-27', '2023-03-29', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-04-12', '2023-04-17', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-04-25', '2023-04-25', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-05-02', '2023-05-03', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-05-08', '2023-05-10', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-05-22', '2023-05-22', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-05-31', '2023-06-01', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-06-07', '2023-06-07', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-06-20', '2023-06-22', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-07-20', '2023-07-20', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-08-14', '2023-08-14', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-08-21', '2023-08-21', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-09-04', '2023-09-07', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-09-18', '2023-09-21', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-10-02', '2023-10-05', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-10-16', '2023-11-03', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-11-07', '2023-11-08', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-11-09', '2023-11-10', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 160 egenmelding · tilfelle 5', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-11-13', '2023-12-01', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-12-07', '2023-12-08', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 160 egenmelding · tilfelle 6', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-12-13', '2023-12-15', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-01-03', '2024-01-05', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-01-15', '2024-01-18', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-01-29', '2024-01-31', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-02-07', '2024-02-09', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-02-13', '2024-02-22', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-02-27', '2024-03-07', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-03-12', '2024-03-21', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-03-26', '2024-03-26', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-04-03', '2024-04-04', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-04-09', '2024-04-11', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-04-15', '2024-04-18', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-04-23', '2024-05-08', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-05-13', '2024-05-16', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-05-21', '2024-05-23', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-05-27', '2024-06-10', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-06-25', '2024-06-27', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-07-16', '2024-07-17', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-08-06', '2024-08-07', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-08-21', '2024-08-23', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-08-27', '2024-08-29', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-09-03', '2024-09-06', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-09-10', '2024-09-12', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-09-18', '2024-09-20', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-09-24', '2024-09-25', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-10-01', '2024-10-03', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-10-08', '2024-10-17', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-10-21', '2024-10-24', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-10-29', '2024-11-08', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-11-12', '2024-11-14', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-11-18', '2024-11-19', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-12-03', '2024-12-05', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-12-10', '2024-12-20', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-12-25', '2024-12-25', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-12-30', '2025-01-10', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-01-14', '2025-01-23', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-01-27', '2025-01-30', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-02-04', '2025-02-06', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-02-11', '2025-02-13', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-02-17', '2025-04-17', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-04-22', '2025-06-06', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-06-10', '2025-06-13', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-06-23', '2025-06-26', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-06-30', '2025-07-11', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-08-04', '2025-09-24', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-09-29', '2025-10-30', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-11-03', '2025-11-27', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-12-01', '2025-12-19', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-12-23', '2025-12-26', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-01-02', '2026-03-05', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-03-09', '2026-05-15', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-05-19', '2026-06-11', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-06-15', '2026-07-17', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-07-27', '2026-08-27', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-08-31', '2026-10-26', 'godkjent', 'SAP/Excel · Ansattfravær Ingrid · 170 sykmelding (under 16 dg)', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
