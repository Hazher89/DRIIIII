-- Bot/Trekk: push-varsel til bedriftsansvarlig i portalen (som bilkontroll).

CREATE OR REPLACE FUNCTION public.queue_partner_deduction_push(
  p_company_id UUID,
  p_profile_id UUID,
  p_fcm_token TEXT,
  p_title TEXT,
  p_body TEXT,
  p_case_id UUID,
  p_description TEXT DEFAULT 'Bot/trekk → bedriftsansvarlig (push)'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_id UUID;
  tok TEXT := trim(coalesce(p_fcm_token, ''));
BEGIN
  IF tok = '' OR p_profile_id IS NULL OR p_case_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.push_outbox o
    WHERE o.reference_type = 'partner_deduction_cases'
      AND o.reference_id = p_case_id
      AND o.fcm_token = tok
      AND o.created_at > now() - interval '10 minutes'
  ) THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.push_outbox (
    company_id,
    profile_id,
    fcm_token,
    title,
    body,
    data,
    category,
    reference_type,
    reference_id,
    description
  )
  VALUES (
    p_company_id,
    p_profile_id,
    tok,
    left(trim(p_title), 120),
    left(trim(p_body), 500),
    jsonb_build_object(
      'type', 'partner_deduction',
      'case_id', p_case_id::text
    ),
    'partner_deduction',
    'partner_deduction_cases',
    p_case_id,
    p_description
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_partner_deduction_owner_push(
  p_company_id UUID,
  p_partner_id UUID,
  p_case_id UUID,
  p_title TEXT,
  p_body TEXT
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d RECORD;
  n INT := 0;
  sent TEXT[] := ARRAY[]::TEXT[];
BEGIN
  FOR d IN
    SELECT DISTINCT ON (upd.fcm_token)
      ppa.profile_id,
      upd.fcm_token
    FROM public.partner_portal_accounts ppa
    JOIN public.user_push_devices upd
      ON upd.profile_id = ppa.profile_id
     AND upd.is_active = true
    JOIN public.profiles pr ON pr.id = ppa.profile_id AND coalesce(pr.is_active, true) = true
    WHERE ppa.partner_id = p_partner_id
      AND ppa.is_active = true
      AND ppa.profile_id IS NOT NULL
      AND coalesce(ppa.account_kind, 'owner') IN ('owner', 'admin')
      AND ppa.partner_vehicle_id IS NULL
    ORDER BY upd.fcm_token, upd.last_seen_at DESC
  LOOP
    IF d.fcm_token IS NOT NULL AND NOT (d.fcm_token = ANY (sent)) THEN
      IF public.queue_partner_deduction_push(
        p_company_id, d.profile_id, d.fcm_token, p_title, p_body, p_case_id
      ) IS NOT NULL THEN
        n := n + 1;
      END IF;
      sent := array_append(sent, d.fcm_token);
    END IF;
  END LOOP;

  FOR d IN
    SELECT DISTINCT ppa.profile_id, pr.fcm_token
    FROM public.partner_portal_accounts ppa
    JOIN public.profiles pr ON pr.id = ppa.profile_id
    WHERE ppa.partner_id = p_partner_id
      AND ppa.is_active = true
      AND ppa.profile_id IS NOT NULL
      AND coalesce(ppa.account_kind, 'owner') IN ('owner', 'admin')
      AND ppa.partner_vehicle_id IS NULL
      AND nullif(trim(pr.fcm_token), '') IS NOT NULL
  LOOP
    IF d.fcm_token IS NOT NULL AND NOT (d.fcm_token = ANY (sent)) THEN
      IF public.queue_partner_deduction_push(
        p_company_id, d.profile_id, d.fcm_token, p_title, p_body, p_case_id
      ) IS NOT NULL THEN
        n := n + 1;
      END IF;
      sent := array_append(sent, d.fcm_token);
    END IF;
  END LOOP;

  RETURN n;
END;
$$;

DROP FUNCTION IF EXISTS public.resend_partner_deduction_notification(UUID, BOOLEAN, BOOLEAN);

CREATE OR REPLACE FUNCTION public.resend_partner_deduction_notification(
  p_case_id UUID,
  p_notify_sms BOOLEAN DEFAULT true,
  p_notify_email BOOLEAN DEFAULT true,
  p_notify_push BOOLEAN DEFAULT false
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
  v_push_title TEXT;
  v_push_body TEXT;
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

  v_push_title := format('Trekk registrert — %s', v_case.case_number);
  v_push_body := format(
    '%s: kr %s,-. %s Se detaljer i portalen under Trekk.',
    v_case.template_title,
    trim(to_char(v_case.amount_nok, '999999990')),
    v_case.short_description
  );

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

  IF p_notify_push THEN
    PERFORM public.notify_partner_deduction_owner_push(
      v_case.company_id,
      v_case.partner_id,
      v_case.id,
      v_push_title,
      v_push_body
    );
    UPDATE public.partner_deduction_cases
    SET notified_at = coalesce(notified_at, now()),
        status = CASE WHEN status = 'registered' THEN 'notified' ELSE status END
    WHERE id = v_case.id;
  END IF;

  SELECT * INTO v_case FROM public.partner_deduction_cases WHERE id = p_case_id;
  RETURN v_case;
END;
$$;

GRANT EXECUTE ON FUNCTION public.queue_partner_deduction_push(UUID, UUID, TEXT, TEXT, TEXT, UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.notify_partner_deduction_owner_push(UUID, UUID, UUID, TEXT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resend_partner_deduction_notification(UUID, BOOLEAN, BOOLEAN, BOOLEAN) TO authenticated, service_role;
