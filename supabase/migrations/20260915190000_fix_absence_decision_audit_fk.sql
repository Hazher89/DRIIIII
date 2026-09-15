-- Godkjenning av fravær feilet: e-post-audit ble skrevet med email_outbox_id
-- i sms_outbox_id-kolonnen → FK 23503 og hele UPDATE rullet tilbake.

CREATE OR REPLACE FUNCTION public.log_notification_audit(
  p_company_id UUID,
  p_event_channel TEXT,
  p_category TEXT,
  p_setting_key TEXT,
  p_recipient TEXT,
  p_user_id UUID,
  p_status TEXT,
  p_skip_reason TEXT,
  p_description TEXT,
  p_sms_outbox_id UUID DEFAULT NULL,
  p_email_outbox_id UUID DEFAULT NULL,
  p_partner_id UUID DEFAULT NULL,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sms UUID := p_sms_outbox_id;
  v_email UUID := p_email_outbox_id;
BEGIN
  -- Unngå FK-feil som stopper forretningstransaksjoner (f.eks. fraværsgodkjenning).
  IF v_sms IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.sms_outbox s WHERE s.id = v_sms
  ) THEN
    v_sms := NULL;
  END IF;
  IF v_email IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.email_outbox e WHERE e.id = v_email
  ) THEN
    v_email := NULL;
  END IF;

  INSERT INTO public.notification_audit (
    company_id, partner_id, event_channel, category, setting_key,
    recipient, user_id, status, skip_reason, description,
    sms_outbox_id, email_outbox_id, reference_type, reference_id
  ) VALUES (
    p_company_id, p_partner_id, p_event_channel, p_category, p_setting_key,
    p_recipient, p_user_id, p_status, p_skip_reason, p_description,
    v_sms, v_email, p_reference_type, p_reference_id
  );
EXCEPTION
  WHEN foreign_key_violation THEN
    -- Siste sikkerhetsnett: logg uten outbox-pekere.
    INSERT INTO public.notification_audit (
      company_id, partner_id, event_channel, category, setting_key,
      recipient, user_id, status, skip_reason, description,
      sms_outbox_id, email_outbox_id, reference_type, reference_id
    ) VALUES (
      p_company_id, p_partner_id, p_event_channel, p_category, p_setting_key,
      p_recipient, p_user_id, p_status,
      coalesce(p_skip_reason, 'outbox_fk_skipped'),
      p_description,
      NULL, NULL, p_reference_type, p_reference_id
    );
  WHEN OTHERS THEN
    NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_absence_decision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _phone TEXT;
  _email TEXT;
  _status_label TEXT;
  _msg TEXT;
  _push_body TEXT;
  _email_body TEXT;
  _push_title TEXT;
  _sms_id UUID;
  _email_id UUID;
BEGIN
  IF tg_op <> 'UPDATE' THEN
    RETURN new;
  END IF;

  IF old.status IS NOT DISTINCT FROM new.status THEN
    RETURN new;
  END IF;

  IF old.status <> 'ventende'::public.absence_status
     OR new.status NOT IN (
       'godkjent'::public.absence_status,
       'avvist'::public.absence_status
     ) THEN
    RETURN new;
  END IF;

  IF new.user_id IS NULL THEN
    RETURN new;
  END IF;

  BEGIN
    _status_label := CASE
      WHEN new.status = 'godkjent'::public.absence_status THEN 'godkjent'
      ELSE 'avvist'
    END;
    _push_title := 'Fravær ' || _status_label;

    _msg :=
      'DriftPro: ' || coalesce(new.type::text, 'fravær') || ' '
      || _status_label || ' '
      || to_char(new.start_date, 'DD.MM') || '–'
      || to_char(new.end_date, 'DD.MM') || '.';

    _push_body := _msg
      || CASE
           WHEN coalesce(new.decision_comment, '') <> ''
           THEN ' ' || left(new.decision_comment, 120)
           ELSE ''
         END;

    _email_body :=
      'Din fraværssøknad er ' || _status_label || '.' || E'\n\n'
      || 'Type: ' || coalesce(new.type::text, 'ukjent') || E'\n'
      || 'Periode: ' || to_char(new.start_date, 'DD.MM.YYYY')
      || ' – ' || to_char(new.end_date, 'DD.MM.YYYY')
      || CASE
           WHEN coalesce(new.decision_comment, '') <> ''
           THEN E'\n\nKommentar: ' || new.decision_comment
           ELSE ''
         END;

    SELECT
      coalesce(phone_normalized, phone),
      email
    INTO _phone, _email
    FROM public.profiles
    WHERE id = new.user_id;

    PERFORM public.queue_push_to_profile_if_allowed(
      new.company_id,
      new.user_id,
      _push_title,
      _push_body,
      'absence',
      'absences',
      new.id,
      'absence_decision',
      'Fravær beslutning (push)',
      false,
      jsonb_build_object(
        'type', 'absence_decision',
        'reference_type', 'absences',
        'reference_id', new.id::text,
        'category', 'absence',
        'status', new.status::text
      )
    );

    IF public.company_sms_enabled(new.company_id, 'absence_decision')
       AND public.user_accepts_sms(new.user_id)
       AND public.user_effective_notify_channel(new.user_id)
           NOT IN (
             'none'::public.notification_channel,
             'email'::public.notification_channel
           )
       AND coalesce(_phone, '') <> '' THEN
      _sms_id := public.queue_sms(
        new.company_id,
        _phone,
        _msg,
        'absence',
        'absences',
        new.id,
        new.user_id,
        auth.uid()
      );
      IF _sms_id IS NOT NULL THEN
        PERFORM public.log_notification_audit(
          new.company_id, 'sms', 'absence', 'absence_decision',
          _phone, new.user_id, 'queued', NULL,
          'Fravær beslutning (SMS)', _sms_id, NULL, NULL, 'absences', new.id
        );
      END IF;
    ELSIF NOT public.company_sms_enabled(new.company_id, 'absence_decision') THEN
      PERFORM public.log_notification_audit(
        new.company_id, 'sms', 'absence', 'absence_decision',
        coalesce(_phone, ''), new.user_id, 'skipped', 'company_channel_off',
        'Fravær beslutning (SMS)', NULL, NULL, NULL, 'absences', new.id
      );
    END IF;

    IF public.company_email_enabled(new.company_id, 'absence_decision')
       AND public.user_accepts_email(new.user_id)
       AND public.user_effective_notify_channel(new.user_id)
           NOT IN (
             'none'::public.notification_channel,
             'sms'::public.notification_channel
           )
       AND coalesce(_email, '') <> '' THEN
      _email_id := public.queue_email(
        new.company_id,
        _email,
        _push_title,
        _email_body,
        'absence',
        'absences',
        new.id,
        'Fravær beslutning (e-post)',
        new.user_id,
        auth.uid()
      );
      IF _email_id IS NOT NULL THEN
        -- Viktig: email_outbox_id er 11. argument (ikke sms_outbox_id).
        PERFORM public.log_notification_audit(
          new.company_id, 'email', 'absence', 'absence_decision',
          _email, new.user_id, 'queued', NULL,
          'Fravær beslutning (e-post)', NULL, _email_id, NULL, 'absences', new.id
        );
      END IF;
    ELSIF NOT public.company_email_enabled(new.company_id, 'absence_decision') THEN
      PERFORM public.log_notification_audit(
        new.company_id, 'email', 'absence', 'absence_decision',
        coalesce(_email, ''), new.user_id, 'skipped', 'company_channel_off',
        'Fravær beslutning (e-post)', NULL, NULL, NULL, 'absences', new.id
      );
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      -- Varsling skal aldri blokkere godkjenning/avvisning.
      NULL;
  END;

  RETURN new;
END;
$$;

COMMENT ON FUNCTION public.notify_absence_decision IS
  'Ved godkjent/avvist: push + SMS + e-post til søker. Feil i varsling stopper ikke statusendring.';
