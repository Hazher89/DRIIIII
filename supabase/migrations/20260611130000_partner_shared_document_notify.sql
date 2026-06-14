-- Varsel ved opplasting til fellesmappe (samarbeid): valgfri SMS/e-post til valgte partnere.

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

    IF ch IN ('sms', 'both') THEN
      sms_n := sms_n + public.notify_partner_owner_phones(
        doc.company_id, pid, msg,
        'partner_shared_routine', 'partner_shared_routine',
        'partner_shared_documents', doc.id,
        'Fellesmappe — SMS'
      );
    END IF;

    IF ch IN ('email', 'both') THEN
      email_n := email_n + public.notify_partner_owner_emails(
        doc.company_id, pid, sub, body,
        'partner_shared_routine', 'partner_shared_routine',
        'partner_shared_documents', doc.id,
        'Fellesmappe — e-post'
      );
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

GRANT EXECUTE ON FUNCTION public.notify_partner_shared_document_upload(UUID, UUID[], TEXT)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.notify_partner_shared_document_upload IS
  'Sender valgfritt SMS/e-post/begge til valgte samarbeidspartnere ved ny fil i fellesmappe.';
