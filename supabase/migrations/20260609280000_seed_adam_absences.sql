-- Importer fravær for Adam (125) fra SAP/Excel.
-- Totalt: 7 dager egenmelding, 4 tilfeller. Ingen sykt barn.

DO $$
DECLARE
  v_user_id uuid;
  v_company_id uuid;
  v_dept_id uuid;
BEGIN
  SELECT id, company_id, department_id
  INTO v_user_id, v_company_id, v_dept_id
  FROM public.profiles
  WHERE employee_number = '125'
     OR full_name ILIKE '%Adam%Michta%'
  ORDER BY CASE WHEN employee_number = '125' THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke ansatt Adam (125)';
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
    -- 160 Egenmelding — 4 tilfeller, 7 dager
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-06-23', '2025-06-23', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 1', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-07-14', '2025-07-15', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 2', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-08-07', '2025-08-07', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 3', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-11-26', '2025-11-28', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 4', 2025);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
