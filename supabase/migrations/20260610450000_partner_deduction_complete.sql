-- Bot/Trekk: fullføring — stats, purring på nytt, GRANT, indeks.

GRANT EXECUTE ON FUNCTION public.list_partner_deduction_cases(UUID, TEXT, UUID, INT, INT)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_partner_deduction_stats(p_company_id UUID)
RETURNS TABLE (
  open_count BIGINT,
  invoiced_count BIGINT,
  open_amount NUMERIC,
  invoiced_amount NUMERIC,
  evidence_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    count(*) FILTER (WHERE c.status <> 'invoiced'),
    count(*) FILTER (WHERE c.status = 'invoiced'),
    coalesce(sum(c.amount_nok) FILTER (WHERE c.status <> 'invoiced'), 0),
    coalesce(sum(c.amount_nok) FILTER (WHERE c.status = 'invoiced'), 0),
    (SELECT count(*) FROM public.partner_deduction_evidence e
     JOIN public.partner_deduction_cases c2 ON c2.id = e.case_id
     WHERE c2.company_id = p_company_id)
  FROM public.partner_deduction_cases c
  WHERE c.company_id = p_company_id
    AND EXISTS (
      SELECT 1 FROM public.profiles pr
      WHERE pr.id = auth.uid() AND pr.company_id = p_company_id
    );
$$;

CREATE OR REPLACE FUNCTION public.resend_partner_deduction_notification(
  p_case_id UUID,
  p_notify_sms BOOLEAN DEFAULT true,
  p_notify_email BOOLEAN DEFAULT true
)
RETURNS public.partner_deduction_cases
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_case public.partner_deduction_cases%ROWTYPE;
  v_partner public.partners%ROWTYPE;
  v_phone TEXT;
  v_email TEXT;
  v_sms TEXT;
  v_subject TEXT;
  v_body TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_case FROM public.partner_deduction_cases WHERE id = p_case_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sak ikke funnet';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND company_id = v_case.company_id
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  SELECT * INTO v_partner FROM public.partners WHERE id = v_case.partner_id;
  v_phone := nullif(trim(v_partner.phone), '');
  v_email := nullif(trim(v_partner.email), '');

  v_sms := coalesce(
    nullif(trim(v_case.notification_sms_body), ''),
    format(
      'Hei %s. MAVI Logistikk — sak %s: %s. Trekk kr %s,-. %s Mvh MAVI Logistikk',
      v_partner.name, v_case.case_number, v_case.template_title,
      trim(to_char(v_case.amount_nok, '999999990')),
      v_case.short_description
    )
  );
  v_sms := replace(v_sms, '{sak}', v_case.case_number);

  v_subject := coalesce(
    nullif(trim(v_case.notification_email_subject), ''),
    format('Trekk registrert — sak %s — %s', v_case.case_number, v_partner.name)
  );
  v_subject := replace(v_subject, '{sak}', v_case.case_number);

  v_body := coalesce(
    nullif(trim(v_case.notification_email_body), ''),
    format(
      E'Hei %s,\n\nSak %s\nKategori: %s\nBeløp: kr %s,-\n\n%s\n\nMvh MAVI Logistikk AS',
      v_partner.name, v_case.case_number, v_case.template_title,
      trim(to_char(v_case.amount_nok, '999999990')),
      v_case.short_description
    )
  );
  v_body := replace(v_body, '{sak}', v_case.case_number);

  IF EXISTS (SELECT 1 FROM public.partner_deduction_evidence e WHERE e.case_id = v_case.id) THEN
    IF v_sms NOT LIKE '%portalen%' AND v_sms NOT LIKE '%Trekk%' THEN
      v_sms := v_sms || ' Bevis finnes i portalen under Trekk.';
    END IF;
    IF v_body NOT LIKE '%portalen%' THEN
      v_body := v_body || E'\n\nVedlagt bevis (bilde/video) er tilgjengelig i bil-eierportalen under «Trekk».';
    END IF;
  END IF;

  IF p_notify_sms AND v_phone IS NOT NULL THEN
    PERFORM public.queue_sms_if_allowed(
      v_case.company_id, NULL, v_phone, v_sms,
      'partner_deduction', 'partner_deduction_cases', v_case.id,
      'partner_compose', 'Bot/trekk varslet via SMS', true
    );
    UPDATE public.partner_deduction_cases
    SET sms_sent = true, notified_at = coalesce(notified_at, now()),
        status = CASE WHEN status = 'registered' THEN 'notified' ELSE status END,
        notification_sms_body = v_sms
    WHERE id = v_case.id;
  END IF;

  IF p_notify_email AND v_email IS NOT NULL THEN
    PERFORM public.queue_email_if_allowed(
      v_case.company_id, NULL, v_email, v_subject, v_body,
      'partner_deduction', 'partner_deduction_cases', v_case.id,
      'partner_compose', 'Bot/trekk varslet via e-post', true
    );
    UPDATE public.partner_deduction_cases
    SET email_sent = true, notified_at = coalesce(notified_at, now()),
        status = CASE WHEN status = 'registered' THEN 'notified' ELSE status END,
        notification_email_subject = v_subject,
        notification_email_body = v_body
    WHERE id = v_case.id;
  END IF;

  SELECT * INTO v_case FROM public.partner_deduction_cases WHERE id = p_case_id;
  RETURN v_case;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_partner_deduction_stats(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resend_partner_deduction_notification(UUID, BOOLEAN, BOOLEAN) TO authenticated, service_role;
