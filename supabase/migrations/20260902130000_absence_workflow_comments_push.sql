-- Fravær: beslutningskommentar, varsling (SMS/e-post/push) ved ny søknad og ved godkjenning/avslag.

ALTER TABLE public.absences
  ADD COLUMN IF NOT EXISTS decision_comment TEXT;

COMMENT ON COLUMN public.absences.decision_comment IS
  'Valgfri kommentar fra leder/admin ved godkjenning eller avslag.';

-- ── Ny / oppdatert ventende søknad → avdelingsledere ────────────────────────

CREATE OR REPLACE FUNCTION public.notify_leaders_on_absence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  employee_name TEXT;
  dept_id UUID;
  sms_body TEXT;
  email_body TEXT;
  push_body TEXT;
  push_title TEXT;
  is_update BOOLEAN;
BEGIN
  IF new.status IS DISTINCT FROM 'ventende'::public.absence_status THEN
    RETURN new;
  END IF;

  is_update := tg_op = 'UPDATE';

  IF is_update THEN
    IF old.status IS DISTINCT FROM 'ventende'::public.absence_status THEN
      RETURN new;
    END IF;
    IF old.start_date IS NOT DISTINCT FROM new.start_date
       AND old.end_date IS NOT DISTINCT FROM new.end_date
       AND old.type IS NOT DISTINCT FROM new.type
       AND coalesce(old.comment, '') IS NOT DISTINCT FROM coalesce(new.comment, '') THEN
      RETURN new;
    END IF;
  END IF;

  SELECT coalesce(p.full_name, 'Ansatt') INTO employee_name
  FROM public.profiles p WHERE p.id = new.user_id;

  dept_id := coalesce(
    new.department_id,
    (SELECT department_id FROM public.profiles WHERE id = new.user_id)
  );

  push_title := CASE WHEN is_update THEN 'Fravær oppdatert' ELSE 'Ny fraværssøknad' END;
  push_body :=
    employee_name || ': ' || coalesce(new.type::text, 'fravær')
    || ' ' || to_char(new.start_date, 'DD.MM')
    || '–' || to_char(new.end_date, 'DD.MM');
  email_body :=
    'Ansatt: ' || employee_name || E'\n'
    || 'Type: ' || coalesce(new.type::text, 'ukjent') || E'\n'
    || 'Periode: ' || to_char(new.start_date, 'DD.MM.YYYY')
    || ' – ' || to_char(new.end_date, 'DD.MM.YYYY') || E'\n'
    || 'Status: ventende'
    || CASE WHEN coalesce(new.comment, '') <> '' THEN E'\n\nKommentar: ' || new.comment ELSE '' END;
  sms_body :=
    'DriftPro: ' || CASE WHEN is_update THEN 'Oppdatert fravær' ELSE 'Nytt fravær' END
    || ' fra ' || employee_name || '.';

  FOR rec IN
    SELECT id, email, coalesce(phone_normalized, phone) AS phone
    FROM public.profiles
    WHERE company_id = new.company_id
      AND is_active = true
      AND is_approved = true
      AND partner_id IS NULL
      AND role <> 'samarbeidspartner'::public.user_role
      AND id IS DISTINCT FROM new.user_id
  LOOP
    IF NOT public.profile_receives_for_department(
      new.company_id, rec.id, dept_id, 'absence_request'
    ) THEN
      CONTINUE;
    END IF;

    PERFORM public.queue_push_to_profile_if_allowed(
      new.company_id,
      rec.id,
      push_title,
      push_body,
      'absence',
      'absences',
      new.id,
      'absence_request',
      CASE WHEN is_update THEN 'Fravær oppdatert (push)' ELSE 'Nytt fravær (push)' END,
      false,
      jsonb_build_object(
        'type', 'absence_request',
        'reference_type', 'absences',
        'reference_id', new.id::text,
        'category', 'absence'
      )
    );

    IF coalesce(rec.phone, '') <> '' THEN
      PERFORM public.queue_sms_if_allowed(
        new.company_id, rec.id, rec.phone,
        sms_body, 'absence', 'absences', new.id,
        'absence_request', 'Fravær → leder (SMS)', false
      );
    END IF;

    IF coalesce(rec.email, '') <> '' THEN
      PERFORM public.queue_email_if_allowed(
        new.company_id, rec.id, rec.email,
        push_title,
        email_body,
        'absence', 'absences', new.id,
        'absence_request', 'Fravær → leder (e-post)', false
      );
    END IF;
  END LOOP;

  RETURN new;
END;
$$;

-- ── Godkjent / avvist → ansatt ──────────────────────────────────────────────

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
  _email_body TEXT;
  _push_title TEXT;
BEGIN
  IF tg_op <> 'UPDATE' THEN
    RETURN new;
  END IF;

  IF old.status IS NOT DISTINCT FROM new.status THEN
    RETURN new;
  END IF;

  IF old.status <> 'ventende'::public.absence_status
     OR new.status NOT IN ('godkjent'::public.absence_status, 'avvist'::public.absence_status) THEN
    RETURN new;
  END IF;

  _status_label := CASE WHEN new.status = 'godkjent'::public.absence_status THEN 'godkjent' ELSE 'avvist' END;
  _push_title := 'Fravær ' || _status_label;

  _msg :=
    'DriftPro: ' || coalesce(new.type::text, 'fravær') || ' '
    || _status_label || ' '
    || to_char(new.start_date, 'DD.MM') || '–' || to_char(new.end_date, 'DD.MM') || '.';

  _email_body :=
    'Din fraværssøknad er ' || _status_label || '.' || E'\n\n'
    || 'Type: ' || coalesce(new.type::text, 'ukjent') || E'\n'
    || 'Periode: ' || to_char(new.start_date, 'DD.MM.YYYY')
    || ' – ' || to_char(new.end_date, 'DD.MM.YYYY')
    || CASE WHEN coalesce(new.decision_comment, '') <> '' THEN E'\n\nKommentar: ' || new.decision_comment ELSE '' END;

  SELECT phone, email INTO _phone, _email
  FROM public.profiles WHERE id = new.user_id;

  PERFORM public.queue_push_to_profile_if_allowed(
    new.company_id,
    new.user_id,
    _push_title,
    _msg,
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

  IF coalesce(_phone, '') <> '' THEN
    PERFORM public.queue_sms_if_allowed(
      new.company_id, new.user_id, _phone,
      _msg, 'absence', 'absences', new.id,
      'absence_decision', 'Fravær beslutning (SMS)', false
    );
  END IF;

  IF coalesce(_email, '') <> '' THEN
    PERFORM public.queue_email_if_allowed(
      new.company_id, new.user_id, _email,
      _push_title,
      _email_body,
      'absence', 'absences', new.id,
      'absence_decision', 'Fravær beslutning (e-post)', false
    );
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_leaders_on_absence ON public.absences;
CREATE TRIGGER trg_notify_leaders_on_absence
  AFTER INSERT OR UPDATE ON public.absences
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_leaders_on_absence();

DROP TRIGGER IF EXISTS trg_notify_absence_decision ON public.absences;
CREATE TRIGGER trg_notify_absence_decision
  AFTER UPDATE OF status, decision_comment ON public.absences
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_absence_decision();
