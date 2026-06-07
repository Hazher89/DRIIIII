-- Per-ansatt varselmottak (overstyrer standard regler). Sanntid fra app.

ALTER TABLE public.notification_event_definitions
  ADD COLUMN IF NOT EXISTS assignable_to_employees BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS default_recipient_rule TEXT NOT NULL DEFAULT 'leaders'
    CHECK (default_recipient_rule IN ('route_ops', 'leaders', 'admins', 'department_leaders', 'none'));

UPDATE public.notification_event_definitions SET
  assignable_to_employees = false,
  default_recipient_rule = 'none'
WHERE id IN (
  'absence_decision', 'ticket_status', 'hms_risk_assigned', 'hms_sja_assigned'
);

UPDATE public.notification_event_definitions SET default_recipient_rule = 'route_ops'
WHERE id IN (
  'partner_route_ack_internal', 'partner_route_pending_internal', 'sap_route_received',
  'partner_document_internal'
);

UPDATE public.notification_event_definitions SET default_recipient_rule = 'admins'
WHERE id IN ('user_approval', 'partner_deactivated_internal');

UPDATE public.notification_event_definitions SET default_recipient_rule = 'department_leaders'
WHERE id = 'absence_request';

UPDATE public.notification_event_definitions SET assignable_to_employees = false, default_recipient_rule = 'none'
WHERE scope = 'partner';

CREATE TABLE IF NOT EXISTS public.profile_notification_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  event_id TEXT NOT NULL REFERENCES public.notification_event_definitions(id) ON DELETE CASCADE,
  subscribed BOOLEAN NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  UNIQUE (profile_id, event_id)
);

CREATE INDEX IF NOT EXISTS idx_profile_notification_subs_company
  ON public.profile_notification_subscriptions (company_id, profile_id);

ALTER TABLE public.profile_notification_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS profile_notification_subs_read ON public.profile_notification_subscriptions;
CREATE POLICY profile_notification_subs_read ON public.profile_notification_subscriptions
  FOR SELECT TO authenticated
  USING (company_id = public.get_user_company_id());

DROP POLICY IF EXISTS profile_notification_subs_write ON public.profile_notification_subscriptions;
CREATE POLICY profile_notification_subs_write ON public.profile_notification_subscriptions
  FOR ALL TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      public.is_company_admin()
      OR public.get_user_role() IN ('admin'::public.user_role, 'superadmin'::public.user_role, 'leder'::public.user_role)
    )
  )
  WITH CHECK (
    company_id = public.get_user_company_id()
    AND (
      public.is_company_admin()
      OR public.get_user_role() IN ('admin'::public.user_role, 'superadmin'::public.user_role, 'leder'::public.user_role)
    )
  );

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
    WHEN 'leaders' THEN
      RETURN p.role IN ('leder'::public.user_role, 'admin'::public.user_role, 'superadmin'::public.user_role);
    WHEN 'admins' THEN
      RETURN p.role IN ('admin'::public.user_role, 'superadmin'::public.user_role);
    WHEN 'department_leaders' THEN
      RETURN p.role IN ('admin'::public.user_role, 'superadmin'::public.user_role)
        OR EXISTS (
          SELECT 1 FROM public.department_leaders dl WHERE dl.profile_id = p_profile_id
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
BEGIN
  SELECT d.id INTO v_event_id
  FROM public.notification_event_definitions d
  WHERE d.setting_key = p_setting_key
    AND d.scope = 'mavi'
    AND d.is_active = true
    AND d.assignable_to_employees = true
  LIMIT 1;

  IF v_event_id IS NULL THEN
    SELECT p.role IN ('leder'::public.user_role, 'admin'::public.user_role, 'superadmin'::public.user_role)
    INTO v_explicit
    FROM public.profiles p
    WHERE p.id = p_profile_id AND p.company_id = p_company_id AND p.is_active AND p.is_approved;
    RETURN coalesce(v_explicit, false);
  END IF;

  SELECT s.subscribed INTO v_explicit
  FROM public.profile_notification_subscriptions s
  WHERE s.profile_id = p_profile_id AND s.event_id = v_event_id;

  IF FOUND THEN
    RETURN v_explicit;
  END IF;

  RETURN public.profile_default_event_subscription(p_company_id, p_profile_id, v_event_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_mavi_partner_internal(
  p_company_id UUID,
  p_setting_key TEXT,
  p_subject TEXT,
  p_body TEXT,
  p_sms_short TEXT,
  p_category TEXT,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id UUID DEFAULT NULL,
  p_description TEXT DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  n INT := 0;
BEGIN
  FOR rec IN
    SELECT p.id, p.email, p.phone_normalized, p.phone
    FROM public.profiles p
    WHERE p.company_id = p_company_id
      AND p.is_active = true
      AND p.is_approved = true
      AND p.role <> 'samarbeidspartner'::public.user_role
      AND p.partner_id IS NULL
  LOOP
    IF NOT public.profile_receives_notification_event(p_company_id, rec.id, p_setting_key) THEN
      CONTINUE;
    END IF;

    IF public.company_sms_enabled(p_company_id, p_setting_key) THEN
      PERFORM public.queue_sms_if_allowed(
        p_company_id, rec.id, coalesce(rec.phone_normalized, rec.phone),
        p_sms_short, p_category, p_reference_type, p_reference_id,
        p_setting_key, p_description, false
      );
      n := n + 1;
    END IF;
    IF public.company_email_enabled(p_company_id, p_setting_key)
       AND coalesce(rec.email, '') <> '' THEN
      PERFORM public.queue_email_if_allowed(
        p_company_id, rec.id, rec.email, p_subject, p_body,
        p_category, p_reference_type, p_reference_id,
        p_setting_key, p_description, false
      );
      n := n + 1;
    END IF;
  END LOOP;
  RETURN n;
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
BEGIN
  FOR rec IN
    SELECT id, email
    FROM public.profiles
    WHERE company_id = new.company_id
      AND is_active = true
      AND is_approved = true
      AND partner_id IS NULL
      AND role <> 'samarbeidspartner'::public.user_role
  LOOP
    IF NOT public.profile_receives_notification_event(new.company_id, rec.id, 'ticket_new') THEN
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
      'Nytt avvik → leder (e-post)',
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
  SELECT coalesce(p.full_name, 'Ansatt') INTO employee_name FROM public.profiles p WHERE p.id = new.user_id;
  FOR rec IN
    SELECT id, email
    FROM public.profiles
    WHERE company_id = new.company_id
      AND is_active = true
      AND is_approved = true
      AND partner_id IS NULL
      AND role <> 'samarbeidspartner'::public.user_role
  LOOP
    IF NOT public.profile_receives_notification_event(new.company_id, rec.id, 'absence_request') THEN
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
      'Nytt fravær → leder (e-post)',
      false
    );
  END LOOP;
  RETURN new;
END;
$$;

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
  p_subscribed boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d public.notification_event_definitions%ROWTYPE;
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

  INSERT INTO public.profile_notification_subscriptions (
    company_id, profile_id, event_id, subscribed, updated_at, updated_by
  )
  VALUES (p_company_id, p_profile_id, p_event_id, p_subscribed, now(), auth.uid())
  ON CONFLICT (profile_id, event_id) DO UPDATE SET
    subscribed = EXCLUDED.subscribed,
    updated_at = now(),
    updated_by = auth.uid();
END;
$$;

CREATE OR REPLACE FUNCTION public.reset_profile_notification_subscriptions(
  p_company_id uuid,
  p_profile_id uuid DEFAULT NULL,
  p_event_id text DEFAULT NULL
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n int;
BEGIN
  IF p_company_id <> public.get_user_company_id() THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  IF NOT (
    public.is_company_admin()
    OR public.get_user_role() IN ('admin'::public.user_role, 'superadmin'::public.user_role, 'leder'::public.user_role)
  ) THEN
    RAISE EXCEPTION 'Kun admin/leder kan nullstille varselmottakere';
  END IF;

  DELETE FROM public.profile_notification_subscriptions s
  WHERE s.company_id = p_company_id
    AND (p_profile_id IS NULL OR s.profile_id = p_profile_id)
    AND (p_event_id IS NULL OR s.event_id = p_event_id);

  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_company_notification_recipient_matrix TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_profile_notification_subscription TO authenticated;
GRANT EXECUTE ON FUNCTION public.reset_profile_notification_subscriptions TO authenticated;
GRANT EXECUTE ON FUNCTION public.profile_receives_notification_event TO authenticated;
