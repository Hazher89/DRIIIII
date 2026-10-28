-- Full historikk for Rafal (ansattnr 107) fra Ansattfravær Excel/SAP.
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
  WHERE employee_number = '107'
     OR full_name ILIKE '%Rafal%'
  ORDER BY CASE WHEN employee_number = '107' THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke ansatt Rafal (107)';
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
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2023-09-27', '2023-09-29', 'godkjent', 'SAP/Excel · Ansattfravær Rafal · 170 sykmelding (under 16 dg)', 2023),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-03-14', '2024-03-14', 'godkjent', 'SAP/Excel · Ansattfravær Rafal · 160 egenmelding · tilfelle 1', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-06-06', '2024-06-21', 'godkjent', 'SAP/Excel · Ansattfravær Rafal · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-07-15', '2024-07-15', 'godkjent', 'SAP/Excel · Ansattfravær Rafal · 160 egenmelding · tilfelle 2', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-08-02', '2024-08-02', 'godkjent', 'SAP/Excel · Ansattfravær Rafal · 160 egenmelding · tilfelle 3', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-09-06', '2024-09-06', 'godkjent', 'SAP/Excel · Ansattfravær Rafal · 160 egenmelding · tilfelle 4', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-10-03', '2024-10-10', 'godkjent', 'SAP/Excel · Ansattfravær Rafal · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-11-19', '2024-11-19', 'godkjent', 'SAP/Excel · Ansattfravær Rafal · 160 egenmelding · tilfelle 5', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-12-16', '2024-12-19', 'godkjent', 'SAP/Excel · Ansattfravær Rafal · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-04-02', '2025-04-02', 'godkjent', 'SAP/Excel · Ansattfravær Rafal · 160 egenmelding · tilfelle 6', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-05-16', '2025-05-16', 'godkjent', 'SAP/Excel · Ansattfravær Rafal · 160 egenmelding · tilfelle 7', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-07-14', '2025-07-15', 'godkjent', 'SAP/Excel · Ansattfravær Rafal · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-08-27', '2025-08-27', 'godkjent', 'SAP/Excel · Ansattfravær Rafal · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-12-02', '2025-12-02', 'godkjent', 'SAP/Excel · Ansattfravær Rafal · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-12-10', '2025-12-12', 'godkjent', 'SAP/Excel · Ansattfravær Rafal · 160 egenmelding · tilfelle 1', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-12-15', '2025-12-19', 'godkjent', 'SAP/Excel · Ansattfravær Rafal · 161 egenmelding barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-02-09', '2026-02-09', 'godkjent', 'SAP/Excel · Ansattfravær Rafal · 160 egenmelding · tilfelle 2', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-02-13', '2026-10-26', 'godkjent', 'SAP/Excel · Ansattfravær Rafal · 170 sykmelding (under 16 dg)', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
