-- Avvik: søkbar ID i varsler + respekter varselinnstillinger ved statusendring.

CREATE INDEX IF NOT EXISTS idx_tickets_company_ticket_number
  ON public.tickets (company_id, ticket_number);

CREATE OR REPLACE FUNCTION public.ticket_public_ref(p_ticket_number integer)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_ticket_number IS NULL THEN 'Avvik'
    ELSE 'Avvik #' || p_ticket_number::text
  END;
$$;

CREATE OR REPLACE FUNCTION public.notify_leaders_on_ticket()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  dept_id uuid;
  reporter_name text;
  assignee_phone text;
  assignee_email text;
  assignee_name text;
  sms_body text;
  ref text;
BEGIN
  ref := public.ticket_public_ref(new.ticket_number);

  SELECT coalesce(full_name, 'Ansatt') INTO reporter_name
  FROM public.profiles WHERE id = new.reported_by;

  dept_id := coalesce(
    new.department_id,
    (SELECT department_id FROM public.profiles WHERE id = new.reported_by)
  );

  IF new.assigned_to IS NOT NULL THEN
    SELECT
      coalesce(full_name, 'Saksbehandler'),
      phone,
      email
    INTO assignee_name, assignee_phone, assignee_email
    FROM public.profiles
    WHERE id = new.assigned_to;

    sms_body :=
      'DriftPro: ' || ref || ' til deg. «'
      || left(coalesce(new.title, 'Uten tittel'), 50)
      || '». Alvor: ' || coalesce(new.severity::text, 'middels')
      || '. Fra: ' || reporter_name
      || '. Logg inn og behandle saken.';

    IF coalesce(assignee_phone, '') <> '' THEN
      PERFORM public.queue_sms_if_allowed(
        new.company_id, new.assigned_to, assignee_phone,
        sms_body, 'ticket_assigned', 'tickets', new.id,
        'ticket_assigned', 'Avvik tildelt saksbehandler', false
      );
    END IF;

    IF coalesce(assignee_email, '') <> '' THEN
      PERFORM public.queue_email_if_allowed(
        new.company_id, new.assigned_to, assignee_email,
        ref || ' — handling kreves',
        'Du er valgt som saksbehandler.' || E'\n\n'
          || ref || E'\n'
          || 'Tittel: ' || coalesce(new.title, 'uten tittel') || E'\n'
          || 'Alvorlighet: ' || coalesce(new.severity::text, 'middels') || E'\n'
          || 'Fra: ' || reporter_name,
        'ticket_assigned', 'tickets', new.id,
        'ticket_assigned', 'Avvik tildelt (e-post)', false
      );
    END IF;

    RETURN new;
  END IF;

  FOR rec IN
    SELECT id, email
    FROM public.profiles
    WHERE company_id = new.company_id
      AND is_active = true
      AND is_approved = true
      AND partner_id IS NULL
      AND role <> 'samarbeidspartner'::public.user_role
  LOOP
    IF NOT public.profile_receives_for_department(
      new.company_id, rec.id, dept_id, 'ticket_new'
    ) THEN
      CONTINUE;
    END IF;

    PERFORM public.queue_email_if_allowed(
      new.company_id,
      rec.id,
      rec.email,
      ref || ' registrert',
      'Tittel: ' || coalesce(new.title, 'uten tittel') || E'\nAlvorlighet: ' || coalesce(new.severity::text, 'middels'),
      'ticket',
      'tickets',
      new.id,
      'ticket_new',
      'Nytt avvik → avdeling (e-post)',
      false
    );
  END LOOP;

  RETURN new;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_ticket_status_sms()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _phone text;
  _msg text;
  _resolver text;
  _status_no text;
  _ref text;
BEGIN
  IF tg_op <> 'UPDATE' THEN
    RETURN new;
  END IF;

  IF old.status IS NOT DISTINCT FROM new.status
     AND old.resolution_comment IS NOT DISTINCT FROM new.resolution_comment THEN
    RETURN new;
  END IF;

  _ref := public.ticket_public_ref(new.ticket_number);

  SELECT coalesce(full_name, 'Leder') INTO _resolver
  FROM public.profiles
  WHERE id = coalesce(new.resolved_by, auth.uid());

  _status_no := CASE new.status::text
    WHEN 'aapen' THEN 'åpen'
    WHEN 'under_behandling' THEN 'under arbeid'
    WHEN 'tiltak_utfort' THEN 'tiltak utført'
    WHEN 'lukket' THEN 'ferdig behandlet'
    ELSE new.status::text
  END;

  IF new.status IN ('tiltak_utfort', 'lukket')
     AND old.status IS DISTINCT FROM new.status THEN
    SELECT phone INTO _phone FROM public.profiles WHERE id = new.reported_by;

    _msg :=
      'DriftPro: ' || _ref || ' «' || left(coalesce(new.title, ''), 40) || '» '
      || 'er ' || _status_no || '. '
      || 'Av: ' || _resolver || '.';

    IF coalesce(new.resolution_comment, '') <> '' THEN
      _msg := _msg || ' ' || left(new.resolution_comment, 120);
    END IF;

    IF coalesce(_phone, '') <> '' THEN
      PERFORM public.queue_sms_if_allowed(
        new.company_id,
        new.reported_by,
        _phone,
        _msg,
        'ticket_resolved',
        'tickets',
        new.id,
        'ticket_status',
        'Avvik ferdig behandlet',
        false
      );
    END IF;
  ELSIF old.status IS DISTINCT FROM new.status THEN
    SELECT phone INTO _phone FROM public.profiles WHERE id = new.reported_by;

    _msg :=
      'DriftPro: ' || _ref || ' «' || left(coalesce(new.title, ''), 40) || '» '
      || 'har status «' || _status_no || '».';

    IF coalesce(_phone, '') <> '' THEN
      PERFORM public.queue_sms_if_allowed(
        new.company_id,
        new.reported_by,
        _phone,
        _msg,
        'ticket_status',
        'tickets',
        new.id,
        'ticket_status',
        'Avvik statusendring',
        false
      );
    END IF;
  END IF;

  IF new.severity IN ('hoy', 'kritisk')
     AND new.status = 'aapen'
     AND new.assigned_to IS NOT NULL
     AND (old.severity IS DISTINCT FROM new.severity OR old.status IS DISTINCT FROM new.status) THEN
    SELECT phone INTO _phone FROM public.profiles WHERE id = new.assigned_to;
    IF coalesce(_phone, '') <> '' THEN
      PERFORM public.queue_sms_if_allowed(
        new.company_id,
        new.assigned_to,
        _phone,
        'DriftPro KRITISK ' || _ref || ': ' || coalesce(new.title, 'Uten tittel'),
        'ticket_critical',
        'tickets',
        new.id,
        'ticket_assigned',
        'Kritisk avvik',
        false
      );
    END IF;
  END IF;

  RETURN new;
END;
$$;
