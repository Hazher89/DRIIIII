-- Bot/Trekk: LogiQrma saksnummer, bilagsnummer og valgbar beskrivelse.

ALTER TABLE public.partner_deduction_cases
  ADD COLUMN IF NOT EXISTS logiqrma_case_number TEXT,
  ADD COLUMN IF NOT EXISTS voucher_number TEXT,
  ADD COLUMN IF NOT EXISTS logistics_description TEXT;

COMMENT ON COLUMN public.partner_deduction_cases.logiqrma_case_number IS
  'Saksnummer i LogiQrma (økonomi).';
COMMENT ON COLUMN public.partner_deduction_cases.voucher_number IS
  'Bilagsnummer i regnskap/LogiQrma.';
COMMENT ON COLUMN public.partner_deduction_cases.logistics_description IS
  'Valgbar beskrivelse for fakturering i LogiQrma.';

DROP FUNCTION IF EXISTS public.create_partner_deduction_case(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, NUMERIC, BOOLEAN, BOOLEAN, TEXT, TEXT, TEXT
);

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
  p_email_body TEXT DEFAULT NULL,
  p_logiqrma_case_number TEXT DEFAULT NULL,
  p_voucher_number TEXT DEFAULT NULL,
  p_logistics_description TEXT DEFAULT NULL
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
    notification_sms_body, notification_email_subject, notification_email_body,
    logiqrma_case_number, voucher_number, logistics_description
  ) VALUES (
    p_company_id, p_partner_id, v_case_number,
    p_template_id, p_template_title, p_short_description, nullif(trim(p_comment), ''),
    v_amount, 'registered', auth.uid(),
    p_sms_body, p_email_subject, p_email_body,
    nullif(trim(p_logiqrma_case_number), ''),
    nullif(trim(p_voucher_number), ''),
    nullif(trim(p_logistics_description), '')
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

CREATE OR REPLACE FUNCTION public.update_partner_deduction_logiqrma(
  p_case_id UUID,
  p_logiqrma_case_number TEXT DEFAULT NULL,
  p_voucher_number TEXT DEFAULT NULL,
  p_logistics_description TEXT DEFAULT NULL
)
RETURNS public.partner_deduction_cases
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_case public.partner_deduction_cases%ROWTYPE;
  v_profile public.profiles%ROWTYPE;
  v_is_superadmin BOOLEAN := public.get_user_role() = 'superadmin'::public.user_role;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_case FROM public.partner_deduction_cases WHERE id = p_case_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sak ikke funnet';
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  IF NOT v_is_superadmin AND v_profile.company_id IS DISTINCT FROM v_case.company_id THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  IF NOT v_is_superadmin AND v_profile.company_id IS DISTINCT FROM v_case.company_id THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  UPDATE public.partner_deduction_cases
  SET
    logiqrma_case_number = nullif(trim(p_logiqrma_case_number), ''),
    voucher_number = nullif(trim(p_voucher_number), ''),
    logistics_description = nullif(trim(p_logistics_description), '')
  WHERE id = p_case_id
  RETURNING * INTO v_case;

  RETURN v_case;
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
  invoiced_by_name TEXT,
  evidence_count BIGINT,
  logiqrma_case_number TEXT,
  voucher_number TEXT,
  logistics_description TEXT
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
    c.invoiced_at, c.invoiced_by, inv.full_name AS invoiced_by_name,
    (SELECT count(*) FROM public.partner_deduction_evidence e WHERE e.case_id = c.id) AS evidence_count,
    c.logiqrma_case_number, c.voucher_number, c.logistics_description
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

GRANT EXECUTE ON FUNCTION public.create_partner_deduction_case TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_partner_deduction_logiqrma TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_partner_deduction_cases(UUID, TEXT, UUID, INT, INT) TO authenticated, service_role;
