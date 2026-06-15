-- Eksplisitt valg SMS/e-post/begge ved opplasting skal følges — ikke overstyres av
-- ch_partner_shared_routine (som ofte er «email»). Kun valgte partnere varsles.

CREATE OR REPLACE FUNCTION public.notify_partner_shared_document_upload(
  p_document_id UUID,
  p_partner_ids UUID[],
  p_channel TEXT DEFAULT 'none'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  doc RECORD;
  pid UUID;
  msg TEXT;
  sub TEXT;
  body TEXT;
  sms_n INT := 0;
  email_n INT := 0;
  partner_n INT := 0;
  ch TEXT := lower(trim(coalesce(p_channel, 'none')));
  rec RECORD;
  v_email TEXT;
  sent_phones TEXT[] := ARRAY[]::TEXT[];
  sent_emails TEXT[] := ARRAY[]::TEXT[];
BEGIN
  IF ch NOT IN ('none', 'sms', 'email', 'both') THEN
    RAISE EXCEPTION 'Ugyldig varselkanal: %', p_channel;
  END IF;

  IF ch = 'none' OR p_partner_ids IS NULL OR cardinality(p_partner_ids) = 0 THEN
    RETURN jsonb_build_object('sms', 0, 'email', 0, 'partners', 0, 'channel', ch);
  END IF;

  SELECT sd.*, c.name AS company_name
  INTO doc
  FROM public.partner_shared_documents sd
  JOIN public.companies c ON c.id = sd.company_id
  WHERE sd.id = p_document_id
    AND sd.is_active = true;

  IF doc IS NULL THEN
    RAISE EXCEPTION 'Fant ikke dokument';
  END IF;

  IF doc.company_id IS DISTINCT FROM public.current_user_company_id() THEN
    RAISE EXCEPTION 'Ingen tilgang til dette dokumentet';
  END IF;

  msg :=
    'Nytt dokument i fellesmappe: «' || coalesce(doc.title, 'Dokument')
    || '». Logg inn i DriftPro (Samarbeidspartner).';
  sub := 'Nytt dokument i fellesmappe: ' || coalesce(doc.title, 'Dokument');
  body := msg || E'\n\nBedrift: ' || coalesce(doc.company_name, '');

  FOREACH pid IN ARRAY p_partner_ids LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.partners p
      WHERE p.id = pid
        AND p.company_id = doc.company_id
        AND p.is_active = true
    ) THEN
      CONTINUE;
    END IF;

    partner_n := partner_n + 1;
    sent_phones := ARRAY[]::TEXT[];
    sent_emails := ARRAY[]::TEXT[];

    IF ch IN ('sms', 'both') THEN
      FOR rec IN SELECT pop.phone FROM public.partner_owner_sms_phones(pid) pop
      LOOP
        IF rec.phone IS NOT NULL AND NOT (rec.phone = ANY (sent_phones)) THEN
          IF public.queue_sms(
            doc.company_id,
            rec.phone,
            msg,
            'partner_shared_routine',
            'partner_shared_documents',
            doc.id,
            NULL,
            auth.uid()
          ) IS NOT NULL THEN
            sms_n := sms_n + 1;
            PERFORM public.log_notification_audit(
              doc.company_id, 'sms', 'partner_shared_routine', 'partner_shared_routine',
              rec.phone, NULL, 'queued', NULL,
              'Fellesmappe — SMS (eksplisitt valg)', NULL, NULL, pid,
              'partner_shared_documents', doc.id
            );
          END IF;
          sent_phones := array_append(sent_phones, rec.phone);
        END IF;
      END LOOP;
    END IF;

    IF ch IN ('email', 'both') THEN
      FOR rec IN
        SELECT login_email AS email
        FROM public.partner_portal_accounts
        WHERE partner_id = pid
          AND is_active = true
          AND coalesce(login_email, '') <> ''
          AND coalesce(account_kind, 'owner') IN ('owner', 'admin')
      LOOP
        v_email := trim(lower(rec.email));
        IF v_email <> '' AND NOT (v_email = ANY (sent_emails)) THEN
          IF public.queue_email(
            doc.company_id, v_email, sub, body,
            'partner_shared_routine', 'partner_shared_documents', doc.id,
            'Fellesmappe — e-post (eksplisitt valg)', NULL, auth.uid()
          ) IS NOT NULL THEN
            email_n := email_n + 1;
            PERFORM public.log_notification_audit(
              doc.company_id, 'email', 'partner_shared_routine', 'partner_shared_routine',
              v_email, NULL, 'queued', NULL,
              'Fellesmappe — e-post (eksplisitt valg)', NULL, NULL, pid,
              'partner_shared_documents', doc.id
            );
          END IF;
          sent_emails := array_append(sent_emails, v_email);
        END IF;
      END LOOP;

      SELECT trim(lower(p.email)) INTO v_email
      FROM public.partners p
      WHERE p.id = pid;

      IF v_email IS NOT NULL AND v_email <> '' AND NOT (v_email = ANY (sent_emails)) THEN
        IF public.queue_email(
          doc.company_id, v_email, sub, body,
          'partner_shared_routine', 'partner_shared_documents', doc.id,
          'Fellesmappe — e-post (eksplisitt valg)', NULL, auth.uid()
        ) IS NOT NULL THEN
          email_n := email_n + 1;
          PERFORM public.log_notification_audit(
            doc.company_id, 'email', 'partner_shared_routine', 'partner_shared_routine',
            v_email, NULL, 'queued', NULL,
            'Fellesmappe — e-post (eksplisitt valg)', NULL, NULL, pid,
            'partner_shared_documents', doc.id
          );
        END IF;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'sms', sms_n,
    'email', email_n,
    'partners', partner_n,
    'channel', ch
  );
END;
$$;

COMMENT ON FUNCTION public.notify_partner_shared_document_upload IS
  'Sender SMS/e-post/begge til kun valgte samarbeidspartnere. Kanalen følger brukerens valg i opplastingsdialogen.';
