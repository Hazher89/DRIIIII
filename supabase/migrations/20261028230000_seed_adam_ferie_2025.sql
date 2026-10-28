-- Ferie 2025 for Adam (ansattnr 125).
-- Virkedager: 29 totalt (over vanlig 25-dagers kvote — historisk import).

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
    AND type = 'ferie'
    AND comment LIKE 'SAP/Excel · Ansattfravær Adam · ferie 2025%';

  PERFORM public.ensure_absence_quota(v_user_id, 2025);

  INSERT INTO public.absences (
    user_id, company_id, department_id, type, start_date, end_date, status, comment, quota_year
  ) VALUES
    (v_user_id, v_company_id, v_dept_id, 'ferie', '2025-01-02', '2025-01-03', 'godkjent', 'SAP/Excel · Ansattfravær Adam · ferie 2025', 2025),
    (v_user_id, v_company_id, v_dept_id, 'ferie', '2025-02-03', '2025-02-04', 'godkjent', 'SAP/Excel · Ansattfravær Adam · ferie 2025', 2025),
    (v_user_id, v_company_id, v_dept_id, 'ferie', '2025-03-17', '2025-03-18', 'godkjent', 'SAP/Excel · Ansattfravær Adam · ferie 2025', 2025),
    (v_user_id, v_company_id, v_dept_id, 'ferie', '2025-05-22', '2025-05-22', 'godkjent', 'SAP/Excel · Ansattfravær Adam · ferie 2025', 2025),
    (v_user_id, v_company_id, v_dept_id, 'ferie', '2025-06-10', '2025-06-11', 'godkjent', 'SAP/Excel · Ansattfravær Adam · ferie 2025', 2025),
    (v_user_id, v_company_id, v_dept_id, 'ferie', '2025-07-21', '2025-08-01', 'godkjent', 'SAP/Excel · Ansattfravær Adam · ferie 2025', 2025),
    (v_user_id, v_company_id, v_dept_id, 'ferie', '2025-08-04', '2025-08-06', 'godkjent', 'SAP/Excel · Ansattfravær Adam · ferie 2025', 2025),
    (v_user_id, v_company_id, v_dept_id, 'ferie', '2025-08-27', '2025-08-29', 'godkjent', 'SAP/Excel · Ansattfravær Adam · ferie 2025', 2025),
    (v_user_id, v_company_id, v_dept_id, 'ferie', '2025-11-20', '2025-11-25', 'godkjent', 'SAP/Excel · Ansattfravær Adam · ferie 2025', 2025);

  -- Rekalkuler brukt ferie for 2025 fra godkjente perioder.
  UPDATE public.absence_quotas q
  SET vacation_days_used = COALESCE((
    SELECT SUM(public.count_ferie_business_days_in_year(a.start_date, a.end_date, 2025))
    FROM public.absences a
    WHERE a.user_id = v_user_id
      AND a.type = 'ferie'
      AND a.status = 'godkjent'
      AND a.start_date <= '2025-12-31'
      AND a.end_date >= '2025-01-01'
  ), 0)
  WHERE q.user_id = v_user_id AND q.year = 2025;

  ALTER TABLE public.absences ENABLE TRIGGER validate_egenmelding_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_sykt_barn_trigger;
  ALTER TABLE public.absences ENABLE TRIGGER validate_ferie_quota_trigger;
END $$;
