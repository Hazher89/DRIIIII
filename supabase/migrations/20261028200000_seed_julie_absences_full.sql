-- Full historikk for Julie (ansattnr 154) fra Ansattfravær Excel/SAP.
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
  WHERE employee_number = '154'
     OR full_name ILIKE '%Julie%'
  ORDER BY CASE WHEN employee_number = '154' THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke ansatt Julie (154)';
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
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-02-26', '2024-02-26', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-03-06', '2024-03-11', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-04-08', '2024-04-08', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-05-31', '2024-06-03', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 160 egenmelding · tilfelle 1', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-07-09', '2024-07-10', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 160 egenmelding · tilfelle 2', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-07-30', '2024-07-31', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 160 egenmelding · tilfelle 3', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-08-29', '2024-08-30', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 160 egenmelding · tilfelle 4', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-09-20', '2024-09-27', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-10-14', '2024-10-18', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-11-12', '2024-11-15', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 160 egenmelding · tilfelle 5', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2024-12-27', '2025-01-02', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 170 sykmelding (under 16 dg)', 2024),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-01-27', '2025-01-28', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-02-03', '2025-02-11', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-03-10', '2025-03-10', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-03-21', '2025-03-21', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 160 egenmelding · tilfelle 6', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-04-22', '2025-04-22', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-05-19', '2025-05-19', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 160 egenmelding · tilfelle 7', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-06-16', '2025-06-18', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 160 egenmelding · tilfelle 8', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-07-21', '2025-07-23', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-08-12', '2025-08-15', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-10-21', '2025-10-21', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 160 egenmelding · tilfelle 9', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-10-29', '2025-10-29', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 160 egenmelding · tilfelle 1', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-12-09', '2025-12-10', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 160 egenmelding · tilfelle 2', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-01-19', '2026-01-20', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-02-10', '2026-02-13', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-02-20', '2026-02-20', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 160 egenmelding · tilfelle 3', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-03-17', '2026-03-18', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2026-05-06', '2026-05-13', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 170 sykmelding (under 16 dg)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-08-27', '2026-08-27', 'godkjent', 'SAP/Excel · Ansattfravær Julie · 160 egenmelding · tilfelle 4', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
