-- Komplett varsel-fiks: avvik/HMS kanaler, per-ansatt SMS/e-post/begge/av, tildelt saksbehandler.

-- ── 1. Per-ansatt kanal (SMS / e-post / begge / av) ─────────────────────────
ALTER TABLE public.profile_notification_subscriptions
  ADD COLUMN IF NOT EXISTS channel public.notification_channel NOT NULL DEFAULT 'both';

-- ticket_assigned skal kunne styres per ansatt (saksbehandler får varsel)
ALTER TABLE public.notification_event_definitions
  DROP CONSTRAINT IF EXISTS notification_event_definitions_default_recipient_rule_check;

UPDATE public.notification_event_definitions SET
  assignable_to_employees = true,
  default_recipient_rule = 'assignee_default',
  title = 'Avvik tildelt meg (saksbehandler)'
WHERE id = 'ticket_assigned';

ALTER TABLE public.notification_event_definitions
  ADD CONSTRAINT notification_event_definitions_default_recipient_rule_check
  CHECK (default_recipient_rule IN (
    'route_ops', 'leaders', 'admins', 'department_leaders',
    'department_scoped', 'assignee_default', 'none'
  ));

-- Sikre at avvik-kanaler ikke er av som standard
UPDATE public.company_sms_settings SET
  ch_ticket_new = CASE WHEN ch_ticket_new = 'none'::public.notification_channel THEN 'both'::public.notification_channel ELSE ch_ticket_new END,
  ch_ticket_assigned = CASE WHEN ch_ticket_assigned = 'none'::public.notification_channel THEN 'both'::public.notification_channel ELSE ch_ticket_assigned END,
  ch_ticket_status = CASE WHEN ch_ticket_status = 'none'::public.notification_channel THEN 'both'::public.notification_channel ELSE ch_ticket_status END,
  ch_ticket_critical = CASE WHEN ch_ticket_critical = 'none'::public.notification_channel THEN 'both'::public.notification_channel ELSE ch_ticket_critical END,
  ch_hms = CASE WHEN ch_hms = 'none'::public.notification_channel THEN 'both'::public.notification_channel ELSE ch_hms END;

-- ── 2. Hjelpefunksjoner ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.profile_subscription_row(
  p_profile_id uuid,
  p_setting_key text,
  OUT subscribed boolean,
  OUT channel public.notification_channel,
  OUT found boolean
)
RETURNS record
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_id text;
BEGIN
  subscribed := false;
  channel := 'both'::public.notification_channel;
  found := false;

  SELECT d.id INTO v_event_id
  FROM public.notification_event_definitions d
  WHERE d.setting_key = p_setting_key
    AND d.scope = 'mavi'
    AND d.is_active = true
  LIMIT 1;

  IF v_event_id IS NULL THEN
    RETURN;
  END IF;

  SELECT s.subscribed, s.channel, true
  INTO subscribed, channel, found
  FROM public.profile_notification_subscriptions s
  WHERE s.profile_id = p_profile_id
    AND s.event_id = v_event_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.profile_event_allows_sms(
  p_company_id uuid,
  p_profile_id uuid,
  p_setting_key text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  sub record;
  receives boolean;
  d public.notification_event_definitions%ROWTYPE;
BEGIN
  IF NOT public.company_sms_enabled(p_company_id, p_setting_key) THEN
    RETURN false;
  END IF;

  IF p_profile_id IS NOT NULL AND NOT public.user_accepts_sms(p_profile_id) THEN
    RETURN false;
  END IF;

  IF p_profile_id IS NOT NULL THEN
    IF public.user_effective_notify_channel(p_profile_id) IN ('none'::public.notification_channel, 'email'::public.notification_channel) THEN
      RETURN false;
    END IF;
  END IF;

  SELECT * INTO sub FROM public.profile_subscription_row(p_profile_id, p_setting_key);
  IF sub.found THEN
    IF NOT sub.subscribed OR sub.channel IN ('none'::public.notification_channel, 'email'::public.notification_channel) THEN
      RETURN false;
    END IF;
    RETURN true;
  END IF;

  receives := public.profile_receives_notification_event(p_company_id, p_profile_id, p_setting_key);
  IF NOT receives THEN
    RETURN false;
  END IF;

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.profile_event_allows_email(
  p_company_id uuid,
  p_profile_id uuid,
  p_setting_key text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  sub record;
  receives boolean;
BEGIN
  IF NOT public.company_email_enabled(p_company_id, p_setting_key) THEN
    RETURN false;
  END IF;

  IF p_profile_id IS NOT NULL AND NOT public.user_accepts_email(p_profile_id) THEN
    RETURN false;
  END IF;

  IF p_profile_id IS NOT NULL THEN
    IF public.user_effective_notify_channel(p_profile_id) IN ('none'::public.notification_channel, 'sms'::public.notification_channel) THEN
      RETURN false;
    END IF;
  END IF;

  SELECT * INTO sub FROM public.profile_subscription_row(p_profile_id, p_setting_key);
  IF sub.found THEN
    IF NOT sub.subscribed OR sub.channel IN ('none'::public.notification_channel, 'sms'::public.notification_channel) THEN
      RETURN false;
    END IF;
    RETURN true;
  END IF;

  receives := public.profile_receives_notification_event(p_company_id, p_profile_id, p_setting_key);
  RETURN receives;
END;
$$;

-- ── 3. Oppdatert mottak-logikk ──────────────────────────────────────────────
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
    WHEN 'assignee_default' THEN
      RETURN p.role IN (
        'leder'::public.user_role,
        'admin'::public.user_role,
        'superadmin'::public.user_role
      );
    ELSE
      RETURN false;
  END CASE;
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

-- ── 4. Kø-funksjoner respekterer per-ansatt kanal ───────────────────────────
CREATE OR REPLACE FUNCTION public.queue_sms_if_allowed(
  p_company_id UUID,
  p_user_id UUID,
  p_phone TEXT,
  p_message TEXT,
  p_category TEXT,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id UUID DEFAULT NULL,
  p_setting_key TEXT DEFAULT 'general',
  p_description TEXT DEFAULT NULL,
  p_partner_scope BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_phone TEXT;
BEGIN
  IF p_partner_scope THEN
    IF NOT public.company_partner_sms_enabled(p_company_id, p_setting_key) THEN
      PERFORM public.log_notification_audit(
        p_company_id, 'sms', p_category, p_setting_key,
        coalesce(p_phone, ''), p_user_id, 'skipped', 'company_channel_off',
        coalesce(p_description, left(p_message, 120)), NULL, NULL, NULL, p_reference_type, p_reference_id
      );
      RETURN NULL;
    END IF;
  ELSIF p_user_id IS NOT NULL THEN
    IF NOT public.profile_event_allows_sms(p_company_id, p_user_id, p_setting_key) THEN
      PERFORM public.log_notification_audit(
        p_company_id, 'sms', p_category, p_setting_key,
        coalesce(p_phone, ''), p_user_id, 'skipped', 'profile_channel_off',
        coalesce(p_description, left(p_message, 120)), NULL, NULL, NULL, p_reference_type, p_reference_id
      );
      RETURN NULL;
    END IF;
  ELSIF NOT public.company_sms_enabled(p_company_id, p_setting_key) THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'sms', p_category, p_setting_key,
      coalesce(p_phone, ''), p_user_id, 'skipped', 'company_channel_off',
      coalesce(p_description, left(p_message, 120)), NULL, NULL, NULL, p_reference_type, p_reference_id
    );
    RETURN NULL;
  END IF;

  v_phone := COALESCE(
    (SELECT phone_normalized FROM public.profiles WHERE id = p_user_id),
    p_phone
  );

  IF coalesce(v_phone, '') = '' THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'sms', p_category, p_setting_key,
      '', p_user_id, 'skipped', 'missing_phone',
      coalesce(p_description, left(p_message, 120)), NULL, NULL, NULL, p_reference_type, p_reference_id
    );
    RETURN NULL;
  END IF;

  v_id := public.queue_sms(
    p_company_id, v_phone, p_message, p_category,
    p_reference_type, p_reference_id, p_user_id, auth.uid()
  );

  IF v_id IS NOT NULL THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'sms', p_category, p_setting_key,
      v_phone, p_user_id, 'queued', NULL,
      coalesce(p_description, left(p_message, 120)), v_id, NULL, NULL, p_reference_type, p_reference_id
    );
  END IF;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.queue_email_if_allowed(
  p_company_id UUID,
  p_user_id UUID,
  p_to_email TEXT,
  p_subject TEXT,
  p_body TEXT,
  p_category TEXT,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id UUID DEFAULT NULL,
  p_setting_key TEXT DEFAULT 'general',
  p_description TEXT DEFAULT NULL,
  p_partner_scope BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_email TEXT;
BEGIN
  IF p_partner_scope THEN
    IF NOT public.company_partner_email_enabled(p_company_id, p_setting_key) THEN
      PERFORM public.log_notification_audit(
        p_company_id, 'email', p_category, p_setting_key,
        coalesce(p_to_email, ''), p_user_id, 'skipped', 'company_channel_off',
        coalesce(p_description, p_subject), NULL, NULL, NULL, p_reference_type, p_reference_id
      );
      RETURN NULL;
    END IF;
  ELSIF p_user_id IS NOT NULL THEN
    IF NOT public.profile_event_allows_email(p_company_id, p_user_id, p_setting_key) THEN
      PERFORM public.log_notification_audit(
        p_company_id, 'email', p_category, p_setting_key,
        coalesce(p_to_email, ''), p_user_id, 'skipped', 'profile_channel_off',
        coalesce(p_description, p_subject), NULL, NULL, NULL, p_reference_type, p_reference_id
      );
      RETURN NULL;
    END IF;
  ELSIF NOT public.company_email_enabled(p_company_id, p_setting_key) THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'email', p_category, p_setting_key,
      coalesce(p_to_email, ''), p_user_id, 'skipped', 'company_channel_off',
      coalesce(p_description, p_subject), NULL, NULL, NULL, p_reference_type, p_reference_id
    );
    RETURN NULL;
  END IF;

  v_email := COALESCE(
    (SELECT email FROM public.profiles WHERE id = p_user_id),
    p_to_email
  );

  IF coalesce(v_email, '') = '' THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'email', p_category, p_setting_key,
      '', p_user_id, 'skipped', 'missing_email',
      coalesce(p_description, p_subject), NULL, NULL, NULL, p_reference_type, p_reference_id
    );
    RETURN NULL;
  END IF;

  v_id := public.queue_email(
    p_company_id,
    v_email,
    p_subject,
    p_body,
    p_category,
    p_reference_type,
    p_reference_id,
    p_description,
    p_user_id,
    auth.uid()
  );

  IF v_id IS NOT NULL THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'email', p_category, p_setting_key,
      v_email, p_user_id, 'queued', NULL,
      coalesce(p_description, p_subject), NULL, v_id, NULL, p_reference_type, p_reference_id
    );
  END IF;

  RETURN v_id;
END;
$$;

-- ── 5. Avvik: tildelt saksbehandler + avdeling (SMS + e-post) ───────────────
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
    IF NOT public.profile_receives_notification_event(
      new.company_id, new.assigned_to, 'ticket_assigned'
    ) THEN
      RETURN new;
    END IF;

    SELECT
      coalesce(full_name, 'Saksbehandler'),
      coalesce(phone_normalized, phone),
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
    SELECT id, email, coalesce(phone_normalized, phone) AS phone
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

    sms_body :=
      'DriftPro: ' || ref || ' i din avdeling. «'
      || left(coalesce(new.title, 'Uten tittel'), 50)
      || '». Alvor: ' || coalesce(new.severity::text, 'middels')
      || '. Fra: ' || reporter_name || '.';

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
        ref || ' registrert',
        'Tittel: ' || coalesce(new.title, 'uten tittel') || E'\nAlvorlighet: ' || coalesce(new.severity::text, 'middels'),
        'ticket', 'tickets', new.id,
        'ticket_new', 'Nytt avvik → avdeling (e-post)', false
      );
    END IF;
  END LOOP;

  RETURN new;
END;
$$;

-- ── 6. Fravær: SMS + e-post ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_leaders_on_absence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  employee_name text;
  dept_id uuid;
  sms_body text;
BEGIN
  SELECT coalesce(p.full_name, 'Ansatt') INTO employee_name
  FROM public.profiles p WHERE p.id = new.user_id;

  dept_id := coalesce(
    new.department_id,
    (SELECT department_id FROM public.profiles WHERE id = new.user_id)
  );

  FOR rec IN
    SELECT id, email, coalesce(phone_normalized, phone) AS phone
    FROM public.profiles
    WHERE company_id = new.company_id
      AND is_active = true
      AND is_approved = true
      AND partner_id IS NULL
      AND role <> 'samarbeidspartner'::public.user_role
  LOOP
    IF NOT public.profile_receives_for_department(
      new.company_id, rec.id, dept_id, 'absence_request'
    ) THEN
      CONTINUE;
    END IF;

    sms_body :=
      'DriftPro: Nytt fravær fra ' || employee_name
      || '. Type: ' || coalesce(new.type::text, 'ukjent')
      || '. Status: ' || coalesce(new.status::text, 'ventende') || '.';

    IF coalesce(rec.phone, '') <> '' THEN
      PERFORM public.queue_sms_if_allowed(
        new.company_id, rec.id, rec.phone,
        sms_body, 'absence', 'absences', new.id,
        'absence_request', 'Nytt fravær (SMS)', false
      );
    END IF;

    IF coalesce(rec.email, '') <> '' THEN
      PERFORM public.queue_email_if_allowed(
        new.company_id, rec.id, rec.email,
        'Nytt fravær registrert',
        'Bruker: ' || employee_name || E'\nType: ' || coalesce(new.type::text, 'ukjent') || E'\nStatus: ' || coalesce(new.status::text, 'ventende'),
        'absence', 'absences', new.id,
        'absence_request', 'Nytt fravær (e-post)', false
      );
    END IF;
  END LOOP;

  RETURN new;
END;
$$;

-- ── 7. Matrise + lagring med kanal ──────────────────────────────────────────
-- PostgreSQL tillater ikke endret returtype/signatur med CREATE OR REPLACE alene.
DROP FUNCTION IF EXISTS public.get_company_notification_recipient_matrix(uuid);
DROP FUNCTION IF EXISTS public.set_profile_notification_subscription(uuid, uuid, text, boolean);

CREATE OR REPLACE FUNCTION public.get_company_notification_recipient_matrix(p_company_id uuid)
RETURNS TABLE (
  profile_id uuid,
  profile_name text,
  profile_email text,
  profile_role text,
  department_name text,
  event_id text,
  setting_key text,
  event_title text,
  category_group text,
  subscribed boolean,
  channel text,
  is_explicit boolean,
  default_recipient_rule text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_company_id <> public.get_user_company_id() THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  RETURN QUERY
  SELECT
    p.id AS profile_id,
    p.full_name AS profile_name,
    p.email AS profile_email,
    p.role::text AS profile_role,
    d.name AS department_name,
    e.id AS event_id,
    e.setting_key,
    e.title AS event_title,
    e.category_group,
    CASE
      WHEN s.id IS NOT NULL THEN s.subscribed
      ELSE public.profile_default_event_subscription(p_company_id, p.id, e.id)
    END AS subscribed,
    CASE
      WHEN s.id IS NOT NULL THEN s.channel::text
      ELSE 'both'::text
    END AS channel,
    (s.id IS NOT NULL) AS is_explicit,
    e.default_recipient_rule
  FROM public.profiles p
  LEFT JOIN public.departments d ON d.id = p.department_id
  CROSS JOIN public.notification_event_definitions e
  LEFT JOIN public.profile_notification_subscriptions s
    ON s.profile_id = p.id AND s.event_id = e.id
  WHERE p.company_id = p_company_id
    AND p.is_active = true
    AND p.is_approved = true
    AND p.partner_id IS NULL
    AND p.role <> 'samarbeidspartner'::public.user_role
    AND e.scope = 'mavi'
    AND e.is_active = true
    AND e.assignable_to_employees = true
  ORDER BY p.full_name, e.category_group, e.sort_order, e.title;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_profile_notification_subscription(
  p_company_id uuid,
  p_profile_id uuid,
  p_event_id text,
  p_subscribed boolean,
  p_channel text DEFAULT 'both'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d public.notification_event_definitions%ROWTYPE;
  ch public.notification_channel;
BEGIN
  IF p_company_id <> public.get_user_company_id() THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  IF NOT (
    public.is_company_admin()
    OR public.get_user_role() IN ('admin'::public.user_role, 'superadmin'::public.user_role, 'leder'::public.user_role)
  ) THEN
    RAISE EXCEPTION 'Kun admin/leder kan endre varselmottakere';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_profile_id AND company_id = p_company_id AND is_active
  ) THEN
    RAISE EXCEPTION 'Ukjent ansatt';
  END IF;

  SELECT * INTO d
  FROM public.notification_event_definitions
  WHERE id = p_event_id AND scope = 'mavi' AND is_active AND assignable_to_employees;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ukjent eller ikke konfigurerbar varseltype: %', p_event_id;
  END IF;

  ch := coalesce(p_channel, 'both')::public.notification_channel;

  IF NOT p_subscribed OR ch = 'none'::public.notification_channel THEN
    INSERT INTO public.profile_notification_subscriptions (
      company_id, profile_id, event_id, subscribed, channel, updated_at, updated_by
    )
    VALUES (p_company_id, p_profile_id, p_event_id, false, 'none'::public.notification_channel, now(), auth.uid())
    ON CONFLICT (profile_id, event_id) DO UPDATE SET
      subscribed = false,
      channel = 'none'::public.notification_channel,
      updated_at = now(),
      updated_by = auth.uid();
    RETURN;
  END IF;

  INSERT INTO public.profile_notification_subscriptions (
    company_id, profile_id, event_id, subscribed, channel, updated_at, updated_by
  )
  VALUES (p_company_id, p_profile_id, p_event_id, true, ch, now(), auth.uid())
  ON CONFLICT (profile_id, event_id) DO UPDATE SET
    subscribed = true,
    channel = EXCLUDED.channel,
    updated_at = now(),
    updated_by = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION public.profile_event_allows_sms TO authenticated;
GRANT EXECUTE ON FUNCTION public.profile_event_allows_email TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_company_notification_recipient_matrix(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_profile_notification_subscription(uuid, uuid, text, boolean, text) TO authenticated;
