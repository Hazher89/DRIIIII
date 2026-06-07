-- Importer fravær for Madyar (103) fra SAP/Excel.
-- Totalt: 3 dager sykt barn (161), ingen egenmelding.

DO $$
DECLARE
  v_user_id uuid;
  v_company_id uuid;
  v_dept_id uuid;
BEGIN
  SELECT id, company_id, department_id
  INTO v_user_id, v_company_id, v_dept_id
  FROM public.profiles
  WHERE employee_number = '103'
     OR full_name ILIKE '%Madyar%Khezernia%'
  ORDER BY CASE WHEN employee_number = '103' THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke ansatt Madyar (103)';
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
    -- 161 Sykt barn — 3 dager
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-02-19', '2026-02-19', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 1', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-03-23', '2026-03-23', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 2', 2026),
    (v_user_id, v_company_id, v_dept_id, 'sykt_barn', '2026-05-28', '2026-05-28', 'godkjent', 'SAP/Excel · 161 barns sykdom · dag 3', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
