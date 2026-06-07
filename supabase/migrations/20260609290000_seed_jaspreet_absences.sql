-- Importer fravær for Jaspreet (18) fra SAP/Excel.
-- Totalt: 11 dager egenmelding (4 tilfeller) + 4 dager sykt barn (2026) = 15 i oversikt.
-- (+ 4 dager sykt barn 2025 som historikk)

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
    -- 161 Sykt barn 2025 (historikk)
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-06-11', '2025-06-11', 'godkjent', 'SAP/Excel · 161 barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-06-12', '2025-06-12', 'godkjent', 'SAP/Excel · 161 barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-07-02', '2025-07-02', 'godkjent', 'SAP/Excel · 161 barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-07-03', '2025-07-03', 'godkjent', 'SAP/Excel · 161 barns sykdom', 2025),
    -- 160 Egenmelding — 4 tilfeller, 11 dager
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-06-16', '2025-06-18', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 1', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-08-11', '2025-08-13', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 2', 2025),
    -- 161 Sykt barn 2026 — teller 1–4
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-01-09', '2026-01-09', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 1', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-01-22', '2026-01-23', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 3', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-03-23', '2026-03-23', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 2', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-03-31', '2026-03-31', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 3', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-05-04', '2026-05-04', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 4', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-05-11', '2026-05-13', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 4', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
