-- Avdelingsledere skal BARE få varsler fra egen avdeling eller eksplisitt tildeling.
-- Ikke bred «leder/admin»-broadcast som superadmin-varsler.

ALTER TABLE public.notification_event_definitions
  DROP CONSTRAINT IF EXISTS notification_event_definitions_default_recipient_rule_check;

ALTER TABLE public.notification_event_definitions
  ADD CONSTRAINT notification_event_definitions_default_recipient_rule_check
  CHECK (default_recipient_rule IN (
    'route_ops', 'leaders', 'admins', 'department_leaders', 'department_scoped', 'none'
  ));

UPDATE public.notification_event_definitions SET default_recipient_rule = 'admins'
WHERE id IN (
  'ticket_critical', 'general', 'equipment', 'hms_general',
  'hms_ros_avvik_signal', 'hms_sja_expired', 'partner_rental_internal'
);

UPDATE public.notification_event_definitions SET default_recipient_rule = 'department_scoped'
WHERE id IN ('ticket_new', 'absence_request');

UPDATE public.notification_event_definitions SET
  default_recipient_rule = 'none',
  assignable_to_employees = false
WHERE id = 'ticket_assigned';

CREATE OR REPLACE FUNCTION public.profile_is_registered_department_leader(p_profile_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.department_leaders dl WHERE dl.profile_id = p_profile_id
  );
$$;

CREATE OR REPLACE FUNCTION public.profile_default_event_subscription(
  p_company_id UUID,
  p_profile_id UUID,
  p_event_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d public.notification_event_definitions%ROWTYPE;
  p public.profiles%ROWTYPE;
BEGIN
  SELECT * INTO d
  FROM public.notification_event_definitions
  WHERE id = p_event_id AND is_active = true;

  IF NOT FOUND OR NOT d.assignable_to_employees OR d.scope <> 'mavi' THEN
    RETURN false;
  END IF;

  SELECT * INTO p
  FROM public.profiles
  WHERE id = p_profile_id AND company_id = p_company_id;

  IF NOT FOUND OR NOT p.is_active OR NOT p.is_approved THEN
    RETURN false;
  END IF;

  IF p.role = 'samarbeidspartner'::public.user_role OR p.partner_id IS NOT NULL THEN
    RETURN false;
  END IF;

  CASE d.default_recipient_rule
    WHEN 'route_ops' THEN
      RETURN public.profile_is_mavi_route_ops_recipient(p_company_id, p_profile_id);
    WHEN 'leaders', 'admins' THEN
      RETURN p.role IN ('admin'::public.user_role, 'superadmin'::public.user_role);
    WHEN 'department_leaders', 'department_scoped' THEN
      RETURN p.role IN ('admin'::public.user_role, 'superadmin'::public.user_role)
        OR public.profile_is_registered_department_leader(p_profile_id);
    ELSE
      RETURN false;
  END CASE;
END;
$$;

CREATE OR REPLACE FUNCTION public.profile_receives_for_department(
  p_company_id uuid,
  p_profile_id uuid,
  p_department_id uuid,
  p_setting_key text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_id text;
  v_explicit boolean;
  v_found boolean := false;
  p public.profiles%ROWTYPE;
BEGIN
  SELECT * INTO p
  FROM public.profiles
  WHERE id = p_profile_id AND company_id = p_company_id;

  IF NOT FOUND OR NOT p.is_active OR NOT p.is_approved THEN
    RETURN false;
  END IF;

  SELECT d.id INTO v_event_id
  FROM public.notification_event_definitions d
  WHERE d.setting_key = p_setting_key
    AND d.scope = 'mavi'
    AND d.is_active = true
  LIMIT 1;

  IF v_event_id IS NOT NULL THEN
    SELECT s.subscribed, true INTO v_explicit, v_found
    FROM public.profile_notification_subscriptions s
    WHERE s.profile_id = p_profile_id AND s.event_id = v_event_id;

    IF v_found THEN
      RETURN v_explicit;
    END IF;
  END IF;

  IF p.role IN ('admin'::public.user_role, 'superadmin'::public.user_role) THEN
    IF v_event_id IS NULL THEN
      RETURN true;
    END IF;
    RETURN public.profile_default_event_subscription(p_company_id, p_profile_id, v_event_id);
  END IF;

  IF p_department_id IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.department_leaders dl
    WHERE dl.profile_id = p_profile_id
      AND dl.department_id = p_department_id
  ) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.profile_receives_notification_event(
  p_company_id UUID,
  p_profile_id UUID,
  p_setting_key TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_id TEXT;
  v_explicit BOOLEAN;
  v_found BOOLEAN := false;
  p public.profiles%ROWTYPE;
BEGIN
  SELECT * INTO p
  FROM public.profiles
  WHERE id = p_profile_id AND company_id = p_company_id;

  IF NOT FOUND OR NOT p.is_active OR NOT p.is_approved THEN
    RETURN false;
  END IF;

  SELECT d.id INTO v_event_id
  FROM public.notification_event_definitions d
  WHERE d.setting_key = p_setting_key
    AND d.scope = 'mavi'
    AND d.is_active = true
    AND d.assignable_to_employees = true
  LIMIT 1;

  IF v_event_id IS NULL THEN
    RETURN p.role IN ('admin'::public.user_role, 'superadmin'::public.user_role);
  END IF;

  SELECT s.subscribed, true INTO v_explicit, v_found
  FROM public.profile_notification_subscriptions s
  WHERE s.profile_id = p_profile_id AND s.event_id = v_event_id;

  IF v_found THEN
    RETURN v_explicit;
  END IF;

  RETURN public.profile_default_event_subscription(p_company_id, p_profile_id, v_event_id);
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
BEGIN
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
      'DriftPro: Nytt avvik til deg. «'
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
        'Nytt avvik — handling kreves',
        'Du er valgt som saksbehandler.' || E'\n\n'
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
      'Nytt avvik registrert',
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

CREATE OR REPLACE FUNCTION public.notify_leaders_on_absence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  employee_name TEXT;
BEGIN
  IF new.status IS DISTINCT FROM 'ventende'::public.absence_status THEN
    RETURN new;
  END IF;

  SELECT coalesce(p.full_name, 'Ansatt') INTO employee_name
  FROM public.profiles p WHERE p.id = new.user_id;

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
      new.company_id, rec.id, new.department_id, 'absence_request'
    ) THEN
      CONTINUE;
    END IF;

    PERFORM public.queue_email_if_allowed(
      new.company_id,
      rec.id,
      rec.email,
      'Nytt fravær registrert',
      'Bruker: ' || employee_name || E'\nType: ' || coalesce(new.type::text, 'ukjent') || E'\nStatus: ' || coalesce(new.status::text, 'ventende'),
      'absence',
      'absences',
      new.id,
      'absence_request',
      'Nytt fravær → avdeling (e-post)',
      false
    );
  END LOOP;

  RETURN new;
END;
$$;

-- Fjern feilaktige manuelle abonnement for avdelingsledere på admin-broadcast.
DELETE FROM public.profile_notification_subscriptions s
USING public.profiles p, public.notification_event_definitions d
WHERE s.profile_id = p.id
  AND s.event_id = d.id
  AND p.role = 'leder'::public.user_role
  AND s.subscribed = true
  AND d.default_recipient_rule IN ('admins', 'leaders', 'route_ops');

DELETE FROM public.profile_notification_subscriptions s
USING public.profiles p, public.notification_event_definitions d
WHERE s.profile_id = p.id
  AND s.event_id = d.id
  AND p.role = 'leder'::public.user_role
  AND s.subscribed = true
  AND d.default_recipient_rule IN ('department_scoped', 'department_leaders')
  AND NOT public.profile_is_registered_department_leader(p.id);

GRANT EXECUTE ON FUNCTION public.profile_receives_for_department TO authenticated;
GRANT EXECUTE ON FUNCTION public.profile_is_registered_department_leader TO authenticated;
