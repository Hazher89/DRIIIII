-- Importer fravær for Julie (154) fra SAP/Excel.
-- Totalt: 8 dager egenmelding, 5 tilfeller. Ingen sykt barn.

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
     OR full_name ILIKE '%Julie%Sayeeda%Eyland%'
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
    -- 160 Egenmelding — 5 tilfeller, 8 dager
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-06-16', '2025-06-18', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 1', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-10-21', '2025-10-21', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 2', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-10-29', '2025-10-29', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 3', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2025-12-09', '2025-12-10', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 4', 2025),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-02-20', '2026-02-20', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 5', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
