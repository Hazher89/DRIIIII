-- Full historikk for Aware (ansattnr 152) fra Ansattfravær Excel/SAP.
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
  WHERE employee_number = '152'
     OR full_name ILIKE '%Aware%'
  ORDER BY CASE WHEN employee_number = '152' THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke ansatt Aware (152)';
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
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-10-30', '2024-11-01', 'godkjent', 'SAP/Excel · Ansattfravær Aware · 160 egenmelding · tilfelle 1', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2024-12-12', '2024-12-13', 'godkjent', 'SAP/Excel · Ansattfravær Aware · 160 egenmelding · tilfelle 2', 2024),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-01-07', '2025-01-09', 'godkjent', 'SAP/Excel · Ansattfravær Aware · 160 egenmelding · tilfelle 3', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykmelding', '2025-01-10', '2025-01-13', 'godkjent', 'SAP/Excel · Ansattfravær Aware · 170 sykmelding (under 16 dg)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-02-04', '2025-02-05', 'godkjent', 'SAP/Excel · Ansattfravær Aware · 160 egenmelding · tilfelle 4', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-03-30', '2026-03-31', 'godkjent', 'SAP/Excel · Ansattfravær Aware · 160 egenmelding · tilfelle 1', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-08-12', '2026-08-14', 'godkjent', 'SAP/Excel · Ansattfravær Aware · 160 egenmelding · tilfelle 2', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-09-10', '2026-09-11', 'godkjent', 'SAP/Excel · Ansattfravær Aware · 160 egenmelding · tilfelle 3', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
