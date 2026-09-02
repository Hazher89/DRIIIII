-- Anonym anmeldelse: kun Tommy / Nico / Hazher — velg én, flere eller alle tre.
-- Aldri avdelingsledere.

ALTER TABLE public.whistleblowing_reports
  ADD COLUMN IF NOT EXISTS recipient_principals text[] NOT NULL DEFAULT ARRAY['tommy','nico','hazher']::text[];

UPDATE public.whistleblowing_reports
SET recipient_principals = ARRAY['tommy','nico','hazher']::text[]
WHERE recipient_principals IS NULL
   OR cardinality(recipient_principals) = 0;

-- Fjern gammel sjekk som tillot leader/both med avd.leder
ALTER TABLE public.whistleblowing_reports
  DROP CONSTRAINT IF EXISTS whistleblowing_reports_recipient_scope_check;

ALTER TABLE public.whistleblowing_reports
  ALTER COLUMN recipient_scope SET DEFAULT 'leadership';

UPDATE public.whistleblowing_reports
SET recipient_scope = 'leadership'
WHERE recipient_scope IS DISTINCT FROM 'leadership';

CREATE OR REPLACE FUNCTION public.notify_whistleblowing_report()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  push_title text := 'Anonym anmeldelse';
  push_body text;
  keys text[];
BEGIN
  keys := coalesce(new.recipient_principals, ARRAY['tommy','nico','hazher']::text[]);
  IF cardinality(keys) = 0 THEN
    keys := ARRAY['tommy','nico','hazher']::text[];
  END IF;

  push_body := left(coalesce(new.title, 'Ny sak'), 120);

  FOR rec IN
    SELECT p.id, p.email, coalesce(p.phone_normalized, p.phone) AS phone
    FROM public.profiles p
    WHERE p.company_id = new.company_id
      AND coalesce(p.is_active, true)
      AND coalesce(p.is_approved, false)
      AND p.partner_id IS NULL
      AND public.profile_is_company_principal(p)
      AND (
        ('tommy' = ANY (keys) AND (
          coalesce(p.employee_number, '') = '100'
          OR lower(p.full_name) LIKE '%tommy%'
        ))
        OR ('nico' = ANY (keys) AND (
          coalesce(p.employee_number, '') = '144'
          OR lower(p.full_name) LIKE '%nicola%'
          OR lower(p.full_name) LIKE '%nico%'
        ))
        OR ('hazher' = ANY (keys) AND (
          coalesce(p.employee_number, '') = '25'
          OR lower(p.full_name) LIKE '%hazher%'
          OR lower(coalesce(p.email, '')) LIKE '%hazher%'
          OR lower(coalesce(p.email, '')) LIKE '%baxigshti%'
        ))
      )
  LOOP
    PERFORM public.queue_push_to_profile_if_allowed(
      new.company_id, rec.id, push_title, push_body,
      'whistleblowing', 'whistleblowing_reports', new.id,
      'general', 'Anonym anmeldelse (push)', false,
      jsonb_build_object(
        'type', 'whistleblowing',
        'reference_type', 'whistleblowing_reports',
        'reference_id', new.id::text
      )
    );
    IF coalesce(rec.phone, '') <> '' THEN
      PERFORM public.queue_sms_if_allowed(
        new.company_id, rec.id, rec.phone,
        'DriftPro: Ny anonym anmeldelse. Logg inn for å lese.',
        'whistleblowing', 'whistleblowing_reports', new.id,
        'general', 'Anonym anmeldelse (SMS)', false
      );
    END IF;
    IF coalesce(rec.email, '') <> '' THEN
      PERFORM public.queue_email_if_allowed(
        new.company_id, rec.id, rec.email,
        push_title,
        'Du har mottatt en anonym anmeldelse.' || E'\n\n'
          || 'Tittel: ' || coalesce(new.title, '') || E'\n\n'
          || left(coalesce(new.description, ''), 2000),
        'whistleblowing', 'whistleblowing_reports', new.id,
        'general', 'Anonym anmeldelse (e-post)', false
      );
    END IF;
  END LOOP;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_whistleblowing_report ON public.whistleblowing_reports;
CREATE TRIGGER trg_notify_whistleblowing_report
  AFTER INSERT ON public.whistleblowing_reports
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_whistleblowing_report();

-- Kun principals kan lese anonyme anmeldelser (ikke avd.ledere)
DROP POLICY IF EXISTS whistleblowing_select_leadership ON public.whistleblowing_reports;
CREATE POLICY whistleblowing_select_leadership ON public.whistleblowing_reports
  FOR SELECT TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND public.profile_is_company_principal(p)
    )
  );

-- Ekstra varsel til valgte principals ved anonymt avvik (én eller flere).
CREATE OR REPLACE FUNCTION public.notify_ticket_selected_profiles(
  p_ticket_id uuid,
  p_profile_ids uuid[]
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  t RECORD;
  rec RECORD;
  n int := 0;
  push_title text;
  push_body text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO t FROM public.tickets WHERE id = p_ticket_id;
  IF NOT FOUND THEN
    RETURN 0;
  END IF;
  IF t.company_id IS DISTINCT FROM public.get_user_company_id() THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;
  IF t.reported_by IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;
  IF coalesce(t.is_anonymous, false) = false THEN
    RETURN 0;
  END IF;

  push_title := 'Anonymt avvik';
  push_body := left(coalesce(t.title, 'Nytt avvik'), 120);

  FOR rec IN
    SELECT p.id, p.email, coalesce(p.phone_normalized, p.phone) AS phone
    FROM public.profiles p
    WHERE p.id = ANY (coalesce(p_profile_ids, ARRAY[]::uuid[]))
      AND p.company_id = t.company_id
      AND coalesce(p.is_active, true)
      AND public.profile_is_company_principal(p)
  LOOP
    PERFORM public.queue_push_to_profile_if_allowed(
      t.company_id, rec.id, push_title, push_body,
      'ticket', 'tickets', t.id,
      'ticket_new', 'Anonymt avvik (push)', false,
      jsonb_build_object(
        'type', 'ticket_new',
        'reference_type', 'tickets',
        'reference_id', t.id::text
      )
    );
    IF coalesce(rec.phone, '') <> '' THEN
      PERFORM public.queue_sms_if_allowed(
        t.company_id, rec.id, rec.phone,
        'DriftPro: Nytt anonymt avvik. Logg inn for å lese.',
        'ticket', 'tickets', t.id,
        'ticket_new', 'Anonymt avvik (SMS)', false
      );
    END IF;
    n := n + 1;
  END LOOP;

  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_ticket_selected_profiles(uuid, uuid[]) TO authenticated;

-- Anonymt avvik: varsle kun tildelt (principal) — aldri avdelingsledere.
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
  sms_body text;
  push_title text;
  push_body text;
  ref text;
  is_anon boolean;
BEGIN
  IF tg_op <> 'INSERT' THEN
    RETURN new;
  END IF;

  is_anon := coalesce(new.is_anonymous, false);
  ref := public.ticket_display_ref(new.trace_ref, new.ticket_number);

  IF is_anon THEN
    reporter_name := 'Anonym';
  ELSE
    SELECT coalesce(full_name, 'Ansatt') INTO reporter_name
    FROM public.profiles WHERE id = new.reported_by;
  END IF;

  dept_id := coalesce(
    new.department_id,
    (SELECT department_id FROM public.profiles WHERE id = new.reported_by)
  );

  push_title := CASE
    WHEN is_anon THEN 'Anonymt avvik'
    ELSE ref || ' registrert'
  END;
  push_body :=
    reporter_name || ': «'
    || left(coalesce(new.title, 'Uten tittel'), 60)
    || '» (' || coalesce(new.severity::text, 'middels') || ')';

  IF new.assigned_to IS NOT NULL THEN
    SELECT coalesce(phone_normalized, phone), email
    INTO assignee_phone, assignee_email
    FROM public.profiles
    WHERE id = new.assigned_to;

    sms_body :=
      'DriftPro: ' || CASE WHEN is_anon THEN 'Anonymt avvik' ELSE ref END
      || ' til deg. «'
      || left(coalesce(new.title, 'Uten tittel'), 50)
      || '». Alvor: ' || coalesce(new.severity::text, 'middels')
      || CASE WHEN is_anon THEN '.' ELSE '. Fra: ' || reporter_name || '.' END;

    PERFORM public.queue_push_to_profile_if_allowed(
      new.company_id, new.assigned_to,
      CASE WHEN is_anon THEN 'Anonymt avvik' ELSE ref || ' — handling kreves' END,
      push_body,
      'ticket', 'tickets', new.id, 'ticket_assigned',
      'Avvik tildelt (push)', false,
      jsonb_build_object(
        'type', 'ticket_assigned',
        'reference_type', 'tickets',
        'reference_id', new.id::text,
        'category', 'ticket'
      )
    );

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
        CASE WHEN is_anon THEN 'Anonymt avvik' ELSE ref || ' — handling kreves' END,
        'Du er valgt som saksbehandler.' || E'\n\n'
          || ref || E'\n'
          || 'Tittel: ' || coalesce(new.title, 'uten tittel') || E'\n'
          || 'Alvorlighet: ' || coalesce(new.severity::text, 'middels')
          || CASE WHEN is_anon THEN '' ELSE E'\nFra: ' || reporter_name END,
        'ticket_assigned', 'tickets', new.id,
        'ticket_assigned', 'Avvik tildelt (e-post)', false
      );
    END IF;
  END IF;

  -- Anonyme avvik skal ALDRI gå til avdelingsledere (kun valgte principals).
  IF is_anon THEN
    RETURN new;
  END IF;

  FOR rec IN
    SELECT id, email, coalesce(phone_normalized, phone) AS phone
    FROM public.profiles
    WHERE company_id = new.company_id
      AND is_active = true
      AND is_approved = true
      AND partner_id IS NULL
      AND role <> 'samarbeidspartner'::public.user_role
      AND id IS DISTINCT FROM new.reported_by
      AND id IS DISTINCT FROM new.assigned_to
  LOOP
    IF NOT public.profile_receives_for_department(
      new.company_id, rec.id, dept_id, 'ticket_new'
    ) THEN
      CONTINUE;
    END IF;

    sms_body :=
      'DriftPro: ' || ref || ' i din avdeling. «'
      || left(coalesce(new.title, 'Uten tittel'), 50)
      || '». Alvor: ' || coalesce(new.severity::text, 'middels')
      || '. Fra: ' || reporter_name || '.';

    PERFORM public.queue_push_to_profile_if_allowed(
      new.company_id, rec.id,
      push_title, push_body,
      'ticket', 'tickets', new.id, 'ticket_new',
      'Nytt avvik (push)', false,
      jsonb_build_object(
        'type', 'ticket_new',
        'reference_type', 'tickets',
        'reference_id', new.id::text,
        'category', 'ticket'
      )
    );

    IF coalesce(rec.phone, '') <> '' THEN
      PERFORM public.queue_sms_if_allowed(
        new.company_id, rec.id, rec.phone,
        sms_body, 'ticket', 'tickets', new.id,
        'ticket_new', 'Nytt avvik → avdeling (SMS)', false
      );
    END IF;

    IF coalesce(rec.email, '') <> '' THEN
      PERFORM public.queue_email_if_allowed(
        new.company_id, rec.id, rec.email,
        push_title,
        'Tittel: ' || coalesce(new.title, 'uten tittel')
          || E'\nAlvorlighet: ' || coalesce(new.severity::text, 'middels')
          || E'\nFra: ' || reporter_name,
        'ticket', 'tickets', new.id,
        'ticket_new', 'Nytt avvik → avdeling (e-post)', false
      );
    END IF;
  END LOOP;

  RETURN new;
END;
$$;

