-- Full historikk for Adam (ansattnr 125) fra Ansattfravær Excel/SAP.
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
  WHERE employee_number = '125'
     OR full_name ILIKE '%Adam%'
  ORDER BY CASE WHEN employee_number = '125' THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke ansatt Adam (125)';
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
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2021-11-15', '2021-11-19', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 170 sykmelding (under 16 dg)', 2021),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-03-16', '2022-03-18', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-07-21', '2022-07-21', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 160 egenmelding · tilfelle 1', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-09-01', '2022-09-09', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-11-15', '2022-11-18', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-01-09', '2023-01-13', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-02-14', '2023-02-16', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 160 egenmelding · tilfelle 2', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-06-05', '2023-06-07', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 160 egenmelding · tilfelle 3', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-09-13', '2023-09-15', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 160 egenmelding · tilfelle 4', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-09-18', '2023-09-28', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-10-24', '2023-10-27', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-12-18', '2023-12-22', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-02-06', '2024-02-08', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 160 egenmelding · tilfelle 5', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-03-11', '2024-03-13', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 160 egenmelding · tilfelle 6', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-05-07', '2024-11-06', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-11-25', '2024-12-18', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-01-06', '2025-01-21', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-03-10', '2025-03-12', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 160 egenmelding · tilfelle 7', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-06-23', '2025-06-23', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 160 egenmelding · tilfelle 8', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-07-14', '2025-07-15', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 160 egenmelding · tilfelle 9', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-08-07', '2025-08-07', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 160 egenmelding · tilfelle 10', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-11-26', '2025-11-28', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 160 egenmelding · tilfelle 1', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-06-19', '2026-06-19', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 160 egenmelding · tilfelle 2', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-06-22', '2026-07-31', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-10-05', '2026-10-07', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 160 egenmelding · tilfelle 3', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-10-21', '2026-10-21', 'godkjent', 'SAP/Excel · Ansattfravær Adam · 160 egenmelding · tilfelle 4', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
