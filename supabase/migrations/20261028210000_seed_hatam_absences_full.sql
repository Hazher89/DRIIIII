-- Full historikk for Hatam (ansattnr 200) fra Ansattfravær Excel/SAP.
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
  WHERE employee_number = '200'
     OR full_name ILIKE '%Hatam%'
  ORDER BY CASE WHEN employee_number = '200' THEN 0 ELSE 1 END
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke ansatt Hatam (200)';
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
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-08-03', '2026-08-05', 'godkjent', 'SAP/Excel · Ansattfravær Hatam · 160 egenmelding · tilfelle 1', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-09-16', '2026-09-18', 'godkjent', 'SAP/Excel · Ansattfravær Hatam · 160 egenmelding · tilfelle 2', 2026),
    (v_user_id, v_company_id, v_dept_id, 'egenmelding', '2026-10-26', '2026-10-26', 'godkjent', 'SAP/Excel · Ansattfravær Hatam · 160 egenmelding · tilfelle 3', 2026);

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
