-- Importer fravær for Karwan (23) fra SAP/Excel.
-- Totalt: 5 dager egenmelding (3 tilfeller) + 3 dager sykt barn (2026) = 8 i oversikt.
-- (+ 5 dager sykt barn 2025 som historikk)

DO $$
DECLARE
  v_user_id uuid;
  v_company_id uuid;
  v_dept_id uuid;
BEGIN
  SELECT id, company_id, department_id
  INTO v_user_id, v_company_id, v_dept_id
  FROM public.profiles
  WHERE employee_number = '23'
     OR full_name ILIKE '%Karwan%Lian%'
  ORDER BY CASE WHEN employee_number = '23' THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke ansatt Karwan (23)';
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
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-06-23', '2025-06-23', 'godkjent', 'SAP/Excel · 161 barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-06-24', '2025-06-24', 'godkjent', 'SAP/Excel · 161 barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-08-04', '2025-08-04', 'godkjent', 'SAP/Excel · 161 barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-08-05', '2025-08-05', 'godkjent', 'SAP/Excel · 161 barns sykdom', 2025),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2025-08-06', '2025-08-06', 'godkjent', 'SAP/Excel · 161 barns sykdom', 2025),
    -- 160 Egenmelding — 3 tilfeller, 5 dager
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-10-20', '2025-10-20', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 1', 2025),
    -- 161 Sykt barn 2026 — teller 1–3
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-01-16', '2026-01-16', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 1', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-02-27', '2026-02-27', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 2', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-05-12', '2026-05-12', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 2', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-05-13', '2026-05-13', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 3', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-05-20', '2026-05-22', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 3', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
