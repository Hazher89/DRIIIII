-- Importer fravær for Rafal (107) fra SAP/Excel.
-- Totalt: 4 dager egenmelding (2 tilfeller) + 9 dager sykt barn = 13 dager.

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
     OR full_name ILIKE '%Rafal%Dopieralski%'
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
    -- 161 Sykt barn — 9 dager
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-07-14', '2025-07-14', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 1', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-07-15', '2025-07-15', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 2', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-08-27', '2025-08-27', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 3', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-12-02', '2025-12-02', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 4', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-12-15', '2025-12-15', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 5', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-12-16', '2025-12-16', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 6', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-12-17', '2025-12-17', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 7', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-12-18', '2025-12-18', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 8', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-12-19', '2025-12-19', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 9', 2025),
    -- 160 Egenmelding — 2 tilfeller, 4 dager
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-12-10', '2025-12-12', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 1', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-02-09', '2026-02-09', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 2', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
