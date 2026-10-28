-- Historisk fravær for Hazher (ansattnr 25) fra Ansattfravær Excel/SAP.
-- 175 «over 16 dg» er omgjort til 170 «under 16 dg» / sykmelding etter avtale.
-- Egenmelding (160), barns sykdom (161), sykmelding (170).

DO $$
DECLARE
  v_user_id uuid;
  v_company_id uuid;
  v_dept_id uuid;
BEGIN
  SELECT id, company_id, department_id
  INTO v_user_id, v_company_id, v_dept_id
  FROM public.profiles
  WHERE employee_number = '25'
     OR full_name ILIKE '%Hazher%'
  ORDER BY CASE WHEN employee_number = '25' THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke ansatt Hazher (25)';
  END IF;

  ALTER TABLE public.absences DISABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences DISABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences DISABLE TRIGGER validate_ferie_quota_trigger;

  DELETE FROM public.absences
  WHERE user_id = v_user_id
    AND comment LIKE 'SAP/Excel · Ansattfravær Hazher%';

  INSERT INTO public.absences (
    user_id, company_id, department_id, type, start_date, end_date, status, comment, quota_year
  ) VALUES
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-11-07', '2022-11-09', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 1', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-12-08', '2022-12-09', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 2', 2022),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2022-12-23', '2022-12-23', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 3', 2022),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-02-06', '2023-02-10', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-03-27', '2023-04-05', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-04-26', '2023-04-27', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 4', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-09-13', '2023-09-15', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 5', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-09-18', '2023-09-29', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-11-24', '2023-11-24', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 6', 2023),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-12-05', '2023-12-08', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2023-12-18', '2023-12-18', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 7', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-04-03', '2024-04-04', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 8', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-05-28', '2024-05-29', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 9', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-09-30', '2024-10-01', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 10', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-10-30', '2024-11-13', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-02-25', '2025-02-25', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 11', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-04-28', '2025-04-29', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 12', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-08-21', '2025-08-22', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 13', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-10-29', '2025-10-30', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-11-03', '2025-11-06', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-01-12', '2026-01-13', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 1', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-01-29', '2026-01-30', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 2', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-02-02', '2026-02-02', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 3', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-02-10', '2026-02-10', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 4', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-05-11', '2026-05-12', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 5', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-05-29', '2026-05-29', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 160 egenmelding · tilfelle 6', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-06-01', '2026-06-01', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 161 egenmelding barns sykdom', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-08-03', '2026-08-07', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-09-28', '2026-10-09', 'godkjent', 'SAP/Excel · Ansattfravær Hazher · 170 sykmelding (under 16 dg)', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
