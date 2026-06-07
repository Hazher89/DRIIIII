-- Historisk fravær for Herish Hameed Alsabaawi (ansattnr 113) fra Excel/SAP.
-- Egenmelding (160) og egenmelding barns sykdom (161).

DO $$
DECLARE
  v_user_id uuid;
  v_company_id uuid;
  v_dept_id uuid;
BEGIN
  SELECT id, company_id, department_id
  INTO v_user_id, v_company_id, v_dept_id
  FROM public.profiles
  WHERE employee_number = '113'
     OR full_name ILIKE '%Herish%Hameed%'
  ORDER BY CASE WHEN employee_number = '113' THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke ansatt Herish (113)';
  END IF;

  ALTER TABLE public.absences DISABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences DISABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences DISABLE TRIGGER validate_ferie_quota_trigger;

  DELETE FROM public.absences
  WHERE user_id = v_user_id
    AND comment = 'Importert historikk (SAP/Excel)';

  INSERT INTO public.absences (
    user_id, company_id, department_id, type, start_date, end_date, status, comment, quota_year
  ) VALUES
    -- Sykt barn 2025
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-06-30', '2025-06-30', 'godkjent', 'Importert historikk (SAP/Excel)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-07-21', '2025-07-21', 'godkjent', 'Importert historikk (SAP/Excel)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-09-11', '2025-09-12', 'godkjent', 'Importert historikk (SAP/Excel)', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-09-19', '2025-09-19', 'godkjent', 'Importert historikk (SAP/Excel)', 2025),
    -- Egenmelding 2025
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-11-17', '2025-11-17', 'godkjent', 'Importert historikk (SAP/Excel) · tilfelle 1', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-11-27', '2025-11-28', 'godkjent', 'Importert historikk (SAP/Excel) · tilfelle 2', 2025),
    -- Sykt barn 2026
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-01-12', '2026-01-12', 'godkjent', 'Importert historikk (SAP/Excel)', 2026),
    -- Egenmelding 2026
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-02-09', '2026-02-09', 'godkjent', 'Importert historikk (SAP/Excel) · tilfelle 3', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-02-16', '2026-02-18', 'godkjent', 'Importert historikk (SAP/Excel)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-03-09', '2026-03-09', 'godkjent', 'Importert historikk (SAP/Excel) · tilfelle 4', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-03-16', '2026-03-16', 'godkjent', 'Importert historikk (SAP/Excel)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-04-09', '2026-04-10', 'godkjent', 'Importert historikk (SAP/Excel)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-05-07', '2026-05-07', 'godkjent', 'Importert historikk (SAP/Excel)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-05-29', '2026-05-29', 'godkjent', 'Importert historikk (SAP/Excel)', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-06-01', '2026-06-01', 'godkjent', 'Importert historikk (SAP/Excel)', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
