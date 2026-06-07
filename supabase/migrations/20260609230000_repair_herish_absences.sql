-- Re-importer fravær for Herish (113) — én rad per Excel-linje, eksakte datoer.
-- Totalt: 5 dager egenmelding (4 tilfeller) + 10 dager sykt barn (2026) = 15 dager i oversikt.

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

  -- Ansettelsesdato for 12-mnd periode (sykt-barn-teller nullstilles 12.01.2026 i Excel).
  UPDATE public.profiles
  SET hire_date = COALESCE(hire_date, '2026-01-12'::date),
      updated_at = NOW()
  WHERE id = v_user_id
    AND hire_date IS NULL;

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
    -- 161 Sykt barn 2025 (historikk, teller 4–8 i Excel)
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-06-30', '2025-06-30', 'godkjent', 'SAP/Excel · 161 barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-07-21', '2025-07-21', 'godkjent', 'SAP/Excel · 161 barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-09-11', '2025-09-11', 'godkjent', 'SAP/Excel · 161 barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-09-12', '2025-09-12', 'godkjent', 'SAP/Excel · 161 barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-09-19', '2025-09-19', 'godkjent', 'SAP/Excel · 161 barns sykdom', 2025),
    -- 160 Egenmelding — 4 tilfeller, 5 dager
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-11-17', '2025-11-17', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 1', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-11-27', '2025-11-28', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 2', 2025),
    -- 161 Sykt barn 2026 — teller 1–10
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-01-12', '2026-01-12', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 1', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-02-09', '2026-02-09', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 3', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-02-16', '2026-02-16', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 2', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-02-17', '2026-02-17', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 3', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-02-18', '2026-02-18', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 4', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-03-09', '2026-03-09', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 4', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-03-16', '2026-03-16', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 5', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-04-09', '2026-04-09', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 6', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-04-10', '2026-04-10', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 7', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-05-07', '2026-05-07', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 8', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-05-29', '2026-05-29', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 9', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-06-01', '2026-06-01', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 10', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
