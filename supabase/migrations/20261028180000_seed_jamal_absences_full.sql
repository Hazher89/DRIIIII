-- Full historikk for Jamal (ansattnr 128) fra Ansattfravær Excel/SAP.
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
  WHERE employee_number = '128'
     OR full_name ILIKE '%Jamal%'
  ORDER BY CASE WHEN employee_number = '128' THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke ansatt Jamal (128)';
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
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-02-16', '2022-02-16', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 160 egenmelding · tilfelle 1', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-03-28', '2022-03-28', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 160 egenmelding · tilfelle 2', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-04-04', '2022-04-05', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-06-08', '2022-06-10', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 160 egenmelding · tilfelle 3', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-11-08', '2022-11-09', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 160 egenmelding · tilfelle 4', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2022-11-10', '2022-11-11', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 170 sykmelding (under 16 dg)', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-03-15', '2023-03-17', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 160 egenmelding · tilfelle 5', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-04-20', '2023-05-04', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-10-30', '2023-11-01', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-01-10', '2024-01-12', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 160 egenmelding · tilfelle 6', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-04-24', '2024-05-03', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-07-16', '2024-07-18', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 160 egenmelding · tilfelle 7', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-11-11', '2024-11-15', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-12-16', '2024-12-18', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 160 egenmelding · tilfelle 8', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-05-19', '2025-05-21', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 160 egenmelding · tilfelle 9', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-08-04', '2025-08-11', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-08-18', '2026-03-06', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-03-10', '2026-03-13', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-03-17', '2026-03-20', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-03-24', '2026-10-26', 'godkjent', 'SAP/Excel · Ansattfravær Jamal · 170 sykmelding (under 16 dg)', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
