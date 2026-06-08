-- Bot/Trekk: registrering av trekk mot samarbeidspartnere + arkiv/fakturering.

CREATE TABLE IF NOT EXISTS public.partner_deduction_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  case_number TEXT NOT NULL,
  template_id TEXT NOT NULL,
  template_title TEXT NOT NULL,
  short_description TEXT NOT NULL,
  comment TEXT,
  amount_nok NUMERIC(12, 2) NOT NULL DEFAULT 500 CHECK (amount_nok >= 0),
  status TEXT NOT NULL DEFAULT 'registered'
    CHECK (status IN ('registered', 'notified', 'invoiced')),
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  notified_at TIMESTAMPTZ,
  sms_sent BOOLEAN NOT NULL DEFAULT false,
  email_sent BOOLEAN NOT NULL DEFAULT false,
  invoiced_at TIMESTAMPTZ,
  invoiced_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  notification_sms_body TEXT,
  notification_email_subject TEXT,
  notification_email_body TEXT,
  UNIQUE (company_id, case_number)
);

CREATE INDEX IF NOT EXISTS idx_partner_deduction_cases_company
  ON public.partner_deduction_cases (company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_partner_deduction_cases_partner
  ON public.partner_deduction_cases (partner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_partner_deduction_cases_status
  ON public.partner_deduction_cases (company_id, status, created_at DESC);

ALTER TABLE public.partner_deduction_cases ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS partner_deduction_cases_select ON public.partner_deduction_cases;
CREATE POLICY partner_deduction_cases_select ON public.partner_deduction_cases
  FOR SELECT USING (
    company_id IN (
      SELECT company_id FROM public.profiles
      WHERE id = auth.uid() AND company_id IS NOT NULL
    )
  );

DROP POLICY IF EXISTS partner_deduction_cases_insert ON public.partner_deduction_cases;
CREATE POLICY partner_deduction_cases_insert ON public.partner_deduction_cases
  FOR INSERT WITH CHECK (
    company_id IN (
      SELECT company_id FROM public.profiles
      WHERE id = auth.uid() AND company_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x
      WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  );

DROP POLICY IF EXISTS partner_deduction_cases_update ON public.partner_deduction_cases;
CREATE POLICY partner_deduction_cases_update ON public.partner_deduction_cases
  FOR UPDATE USING (
    company_id IN (
      SELECT company_id FROM public.profiles
      WHERE id = auth.uid() AND company_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x
      WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  );

CREATE OR REPLACE FUNCTION public.next_partner_deduction_case_number(p_company_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_seq INT;
BEGIN
  SELECT count(*)::INT + 1 INTO v_seq
  FROM public.partner_deduction_cases
  WHERE company_id = p_company_id
    AND case_number LIKE 'BOT-' || v_year || '-%';
  RETURN 'BOT-' || v_year || '-' || lpad(v_seq::TEXT, 4, '0');
END;
$$;

CREATE OR REPLACE FUNCTION public.create_partner_deduction_case(
  p_company_id UUID,
  p_partner_id UUID,
  p_template_id TEXT,
  p_template_title TEXT,
  p_short_description TEXT,
  p_comment TEXT DEFAULT NULL,
  p_amount_nok NUMERIC DEFAULT 500,
  p_notify_sms BOOLEAN DEFAULT false,
  p_notify_email BOOLEAN DEFAULT false,
  p_sms_body TEXT DEFAULT NULL,
  p_email_subject TEXT DEFAULT NULL,
  p_email_body TEXT DEFAULT NULL
)
RETURNS public.partner_deduction_cases
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.partner_deduction_cases%ROWTYPE;
  v_case_number TEXT;
  v_partner public.partners%ROWTYPE;
  v_phone TEXT;
  v_email TEXT;
  v_amount NUMERIC(12, 2);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND company_id = p_company_id
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang til bedrift';
  END IF;

  SELECT * INTO v_partner FROM public.partners
  WHERE id = p_partner_id AND company_id = p_company_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Partner ikke funnet';
  END IF;

  v_amount := coalesce(p_amount_nok, 500);
  IF v_amount < 0 THEN
    RAISE EXCEPTION 'Beløp kan ikke være negativt';
  END IF;

  v_case_number := public.next_partner_deduction_case_number(p_company_id);

  INSERT INTO public.partner_deduction_cases (
    company_id, partner_id, case_number,
    template_id, template_title, short_description, comment,
    amount_nok, status, created_by,
    notification_sms_body, notification_email_subject, notification_email_body
  ) VALUES (
    p_company_id, p_partner_id, v_case_number,
    p_template_id, p_template_title, p_short_description, nullif(trim(p_comment), ''),
    v_amount, 'registered', auth.uid(),
    p_sms_body, p_email_subject, p_email_body
  )
  RETURNING * INTO v_row;

  v_phone := nullif(trim(v_partner.phone), '');
  v_email := nullif(trim(v_partner.email), '');

  IF p_notify_sms AND v_phone IS NOT NULL AND coalesce(p_sms_body, '') <> '' THEN
    PERFORM public.queue_sms_if_allowed(
      p_company_id, NULL, v_phone, replace(p_sms_body, '{sak}', v_case_number),
      'partner_deduction', 'partner_deduction_cases', v_row.id,
      'partner_compose', 'Bot/trekk varslet via SMS', true
    );
    UPDATE public.partner_deduction_cases
    SET sms_sent = true, notified_at = coalesce(notified_at, now()),
        status = CASE WHEN status = 'registered' THEN 'notified' ELSE status END
    WHERE id = v_row.id
    RETURNING * INTO v_row;
  END IF;

  IF p_notify_email AND v_email IS NOT NULL
     AND coalesce(p_email_subject, '') <> ''
     AND coalesce(p_email_body, '') <> '' THEN
    PERFORM public.queue_email_if_allowed(
      p_company_id, NULL, v_email,
      replace(p_email_subject, '{sak}', v_case_number),
      replace(p_email_body, '{sak}', v_case_number),
      'partner_deduction', 'partner_deduction_cases', v_row.id,
      'partner_compose', 'Bot/trekk varslet via e-post', true
    );
    UPDATE public.partner_deduction_cases
    SET email_sent = true, notified_at = coalesce(notified_at, now()),
        status = CASE WHEN status = 'registered' THEN 'notified' ELSE status END
    WHERE id = v_row.id
    RETURNING * INTO v_row;
  END IF;

  RETURN v_row;
END;
$$;

DROP FUNCTION IF EXISTS public.list_partner_deduction_cases(UUID, TEXT, UUID, INT, INT);

CREATE OR REPLACE FUNCTION public.list_partner_deduction_cases(
  p_company_id UUID,
  p_status TEXT DEFAULT NULL,
  p_partner_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 200,
  p_offset INT DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  company_id UUID,
  partner_id UUID,
  partner_name TEXT,
  case_number TEXT,
  template_id TEXT,
  template_title TEXT,
  short_description TEXT,
  comment TEXT,
  amount_nok NUMERIC,
  status TEXT,
  created_by UUID,
  created_by_name TEXT,
  created_at TIMESTAMPTZ,
  notified_at TIMESTAMPTZ,
  sms_sent BOOLEAN,
  email_sent BOOLEAN,
  invoiced_at TIMESTAMPTZ,
  invoiced_by UUID,
  invoiced_by_name TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.id, c.company_id, c.partner_id, p.name AS partner_name,
    c.case_number, c.template_id, c.template_title, c.short_description, c.comment,
    c.amount_nok, c.status, c.created_by,
    cr.full_name AS created_by_name,
    c.created_at, c.notified_at, c.sms_sent, c.email_sent,
    c.invoiced_at, c.invoiced_by, inv.full_name AS invoiced_by_name
  FROM public.partner_deduction_cases c
  JOIN public.partners p ON p.id = c.partner_id
  LEFT JOIN public.profiles cr ON cr.id = c.created_by
  LEFT JOIN public.profiles inv ON inv.id = c.invoiced_by
  WHERE c.company_id = p_company_id
    AND EXISTS (
      SELECT 1 FROM public.profiles pr
      WHERE pr.id = auth.uid() AND pr.company_id = p_company_id
    )
    AND (p_status IS NULL OR c.status = p_status)
    AND (p_partner_id IS NULL OR c.partner_id = p_partner_id)
  ORDER BY c.created_at DESC
  LIMIT greatest(p_limit, 1)
  OFFSET greatest(p_offset, 0);
$$;

CREATE OR REPLACE FUNCTION public.mark_partner_deductions_invoiced(
  p_company_id UUID,
  p_case_ids UUID[]
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
  v_profile public.profiles%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = auth.uid();
  IF NOT FOUND OR v_profile.company_id IS DISTINCT FROM p_company_id THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  IF NOT (
    v_profile.role = 'superadmin'::public.user_role
    OR coalesce(v_profile.employee_number, '') = '144'
    OR lower(v_profile.full_name) LIKE '%nicola%'
    OR lower(v_profile.full_name) LIKE '%nico%'
    OR lower(v_profile.email) LIKE '%nico%'
  ) THEN
    RAISE EXCEPTION 'Kun økonomi (Nico) kan markere som fakturert';
  END IF;

  UPDATE public.partner_deduction_cases
  SET status = 'invoiced',
      invoiced_at = now(),
      invoiced_by = auth.uid()
  WHERE company_id = p_company_id
    AND id = ANY(p_case_ids)
    AND status <> 'invoiced';

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.next_partner_deduction_case_number(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_partner_deduction_case TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_partner_deduction_cases TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_partner_deductions_invoiced TO authenticated, service_role;
