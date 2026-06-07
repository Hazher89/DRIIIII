-- Importer fravær for Aware (152) fra SAP/Excel.
-- Totalt: 2 dager egenmelding, 1 tilfelle.

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
     OR full_name ILIKE '%Aware%Rasoulpour%'
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
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-03-30', '2026-03-31', 'godkjent', 'SAP/Excel · 160 egenmelding · tilfelle 1', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
