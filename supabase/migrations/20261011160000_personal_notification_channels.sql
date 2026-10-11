-- Personlige kanalvalg (SMS / e-post / push) per varseltype.
-- Vanlige ansatte: avvikstatus og ferie/fravær godkjent/avvist.
-- Avdelingsledere, admin og superadmin: alle aktive MAVI-varsler de kan motta.
-- Mangler rad = alle kanaler på (firmaets kanal og samtykke gjelder fortsatt).

ALTER TABLE public.profile_notification_subscriptions
  ADD COLUMN IF NOT EXISTS sms_enabled BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS email_enabled BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS push_enabled BOOLEAN NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.profile_personal_channel_on(
  p_profile_id UUID,
  p_setting_key TEXT,
  p_channel TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub BOOLEAN;
  v_sms BOOLEAN;
  v_email BOOLEAN;
  v_push BOOLEAN;
  v_found BOOLEAN := false;
BEGIN
  IF p_profile_id IS NULL OR coalesce(p_setting_key, '') = '' THEN
    RETURN true;
  END IF;

  SELECT s.subscribed, s.sms_enabled, s.email_enabled, s.push_enabled, true
  INTO v_sub, v_sms, v_email, v_push, v_found
  FROM public.profile_notification_subscriptions s
  JOIN public.notification_event_definitions d ON d.id = s.event_id
  WHERE s.profile_id = p_profile_id
    AND d.is_active = true
    AND (d.setting_key = p_setting_key OR d.id = p_setting_key)
  LIMIT 1;

  IF NOT v_found THEN
    RETURN true;
  END IF;

  IF NOT coalesce(v_sub, false) THEN
    RETURN false;
  END IF;

  IF p_channel = 'sms' THEN
    RETURN coalesce(v_sms, true);
  ELSIF p_channel = 'email' THEN
    RETURN coalesce(v_email, true);
  ELSIF p_channel = 'push' THEN
    RETURN coalesce(v_push, true);
  END IF;

  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.profile_has_personal_channel_row(
  p_profile_id UUID,
  p_setting_key TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profile_notification_subscriptions s
    JOIN public.notification_event_definitions d ON d.id = s.event_id
    WHERE s.profile_id = p_profile_id
      AND d.is_active = true
      AND (d.setting_key = p_setting_key OR d.id = p_setting_key)
  );
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
BEGIN
  IF NOT public.company_sms_enabled(p_company_id, p_setting_key) THEN
    RETURN false;
  END IF;

  IF p_profile_id IS NOT NULL AND NOT public.user_accepts_sms(p_profile_id) THEN
    RETURN false;
  END IF;

  IF p_profile_id IS NOT NULL
     AND public.profile_has_personal_channel_row(p_profile_id, p_setting_key) THEN
    RETURN public.profile_personal_channel_on(p_profile_id, p_setting_key, 'sms');
  END IF;

  IF p_profile_id IS NOT NULL THEN
    IF public.user_effective_notify_channel(p_profile_id) IN (
      'none'::public.notification_channel,
      'email'::public.notification_channel
    ) THEN
      RETURN false;
    END IF;
  END IF;

  SELECT * INTO sub FROM public.profile_subscription_row(p_profile_id, p_setting_key);
  IF sub.found THEN
    IF NOT sub.subscribed OR sub.channel IN (
      'none'::public.notification_channel,
      'email'::public.notification_channel
    ) THEN
      RETURN false;
    END IF;
    RETURN true;
  END IF;

  -- Direkte til den det gjelder (innmelder / søker), ikke lederabonnement.
  IF p_setting_key IN ('ticket_status', 'absence_decision') THEN
    RETURN true;
  END IF;

  receives := public.profile_receives_notification_event(
    p_company_id, p_profile_id, p_setting_key
  );
  RETURN receives;
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

  IF p_profile_id IS NOT NULL
     AND public.profile_has_personal_channel_row(p_profile_id, p_setting_key) THEN
    RETURN public.profile_personal_channel_on(p_profile_id, p_setting_key, 'email');
  END IF;

  IF p_profile_id IS NOT NULL THEN
    IF public.user_effective_notify_channel(p_profile_id) IN (
      'none'::public.notification_channel,
      'sms'::public.notification_channel
    ) THEN
      RETURN false;
    END IF;
  END IF;

  SELECT * INTO sub FROM public.profile_subscription_row(p_profile_id, p_setting_key);
  IF sub.found THEN
    IF NOT sub.subscribed OR sub.channel IN (
      'none'::public.notification_channel,
      'sms'::public.notification_channel
    ) THEN
      RETURN false;
    END IF;
    RETURN true;
  END IF;

  IF p_setting_key IN ('ticket_status', 'absence_decision') THEN
    RETURN true;
  END IF;

  receives := public.profile_receives_notification_event(
    p_company_id, p_profile_id, p_setting_key
  );
  RETURN receives;
END;
$$;

CREATE OR REPLACE FUNCTION public.queue_push_to_profile_if_allowed(
  p_company_id UUID,
  p_profile_id UUID,
  p_title TEXT,
  p_body TEXT,
  p_category TEXT,
  p_reference_type TEXT,
  p_reference_id UUID,
  p_setting_key TEXT,
  p_description TEXT DEFAULT NULL,
  p_partner_scope BOOLEAN DEFAULT false,
  p_data JSONB DEFAULT '{}'::jsonb
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
  v_has_devices BOOLEAN := false;
  v_enabled BOOLEAN;
BEGIN
  IF p_partner_scope THEN
    v_enabled := public.company_partner_push_enabled(p_company_id, p_setting_key);
  ELSE
    v_enabled := public.company_push_enabled(p_company_id, p_setting_key);
  END IF;

  IF NOT v_enabled THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'push', p_category, p_setting_key,
      NULL, p_profile_id, 'skipped', 'company_channel_off',
      coalesce(p_description, left(p_body, 120)), NULL, NULL, NULL, p_reference_type, p_reference_id
    );
    RETURN 0;
  END IF;

  IF p_profile_id IS NOT NULL AND (
    (
      public.profile_has_personal_channel_row(p_profile_id, p_setting_key)
      AND NOT public.profile_personal_channel_on(p_profile_id, p_setting_key, 'push')
    )
    OR (
      NOT public.profile_has_personal_channel_row(p_profile_id, p_setting_key)
      AND public.user_effective_notify_channel(p_profile_id) = 'none'::public.notification_channel
    )
  ) THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'push', p_category, p_setting_key,
      NULL, p_profile_id, 'skipped', 'personal_channel_off',
      coalesce(p_description, left(p_body, 120)), NULL, NULL, NULL, p_reference_type, p_reference_id
    );
    RETURN 0;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.user_push_devices upd
    WHERE upd.profile_id = p_profile_id
      AND upd.is_active = true
      AND nullif(trim(upd.fcm_token), '') IS NOT NULL
  ) INTO v_has_devices;

  FOR d IN
    SELECT DISTINCT ON (upd.fcm_token)
      upd.fcm_token
    FROM public.user_push_devices upd
    WHERE upd.profile_id = p_profile_id
      AND upd.is_active = true
    ORDER BY upd.fcm_token, upd.last_seen_at DESC
  LOOP
    IF d.fcm_token IS NOT NULL AND NOT (d.fcm_token = ANY (sent)) THEN
      IF public.queue_push_if_allowed(
        p_company_id, p_profile_id, d.fcm_token, p_title, p_body,
        p_category, p_reference_type, p_reference_id, p_setting_key, p_description,
        p_partner_scope, p_data
      ) IS NOT NULL THEN
        n := n + 1;
      END IF;
      sent := array_append(sent, d.fcm_token);
    END IF;
  END LOOP;

  IF NOT v_has_devices THEN
    FOR d IN
      SELECT pr.fcm_token
      FROM public.profiles pr
      WHERE pr.id = p_profile_id
        AND nullif(trim(pr.fcm_token), '') IS NOT NULL
    LOOP
      IF d.fcm_token IS NOT NULL AND NOT (d.fcm_token = ANY (sent)) THEN
        IF public.queue_push_if_allowed(
          p_company_id, p_profile_id, d.fcm_token, p_title, p_body,
          p_category, p_reference_type, p_reference_id, p_setting_key, p_description,
          p_partner_scope, p_data
        ) IS NOT NULL THEN
          n := n + 1;
        END IF;
        sent := array_append(sent, d.fcm_token);
      END IF;
    END LOOP;
  END IF;

  IF n = 0 THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'push', p_category, p_setting_key,
      NULL, p_profile_id, 'skipped', 'no_push_devices',
      'Ingen aktiv push-enhet — logg inn i appen og slå på varsler',
      NULL, NULL, NULL, p_reference_type, p_reference_id
    );
  END IF;

  RETURN n;
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
       AND (
         (
           public.profile_has_personal_channel_row(new.user_id, 'absence_decision')
           AND public.profile_personal_channel_on(new.user_id, 'absence_decision', 'sms')
         )
         OR (
           NOT public.profile_has_personal_channel_row(new.user_id, 'absence_decision')
           AND public.user_effective_notify_channel(new.user_id) NOT IN (
             'none'::public.notification_channel,
             'email'::public.notification_channel
           )
         )
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
    ELSIF NOT (
      public.profile_has_personal_channel_row(new.user_id, 'absence_decision')
      AND public.profile_personal_channel_on(new.user_id, 'absence_decision', 'sms')
    ) AND public.profile_has_personal_channel_row(new.user_id, 'absence_decision') THEN
      PERFORM public.log_notification_audit(
        new.company_id, 'sms', 'absence', 'absence_decision',
        coalesce(_phone, ''), new.user_id, 'skipped', 'personal_channel_off',
        'Fravær beslutning (SMS)', NULL, NULL, NULL, 'absences', new.id
      );
    END IF;

    IF public.company_email_enabled(new.company_id, 'absence_decision')
       AND public.user_accepts_email(new.user_id)
       AND (
         (
           public.profile_has_personal_channel_row(new.user_id, 'absence_decision')
           AND public.profile_personal_channel_on(new.user_id, 'absence_decision', 'email')
         )
         OR (
           NOT public.profile_has_personal_channel_row(new.user_id, 'absence_decision')
           AND public.user_effective_notify_channel(new.user_id) NOT IN (
             'none'::public.notification_channel,
             'sms'::public.notification_channel
           )
         )
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
    ELSIF public.profile_has_personal_channel_row(new.user_id, 'absence_decision')
      AND NOT public.profile_personal_channel_on(new.user_id, 'absence_decision', 'email') THEN
      PERFORM public.log_notification_audit(
        new.company_id, 'email', 'absence', 'absence_decision',
        coalesce(_email, ''), new.user_id, 'skipped', 'personal_channel_off',
        'Fravær beslutning (e-post)', NULL, NULL, NULL, 'absences', new.id
      );
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  RETURN new;
END;
$$;

-- E-post og push til innmelder når avvik endrer status (SMS ligger i eksisterende trigger).
CREATE OR REPLACE FUNCTION public.notify_ticket_reporter_channels()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _email TEXT;
  _status_no TEXT;
  _ref TEXT;
  _title TEXT;
  _body TEXT;
BEGIN
  IF tg_op <> 'UPDATE' THEN
    RETURN new;
  END IF;

  IF old.status IS NOT DISTINCT FROM new.status THEN
    RETURN new;
  END IF;

  IF new.reported_by IS NULL THEN
    RETURN new;
  END IF;

  BEGIN
    _ref := public.ticket_display_ref(new.trace_ref, new.ticket_number);
    _status_no := CASE new.status::text
      WHEN 'aapen' THEN 'åpen'
      WHEN 'under_behandling' THEN 'under behandling'
      WHEN 'tiltak_utfort' THEN 'tiltak utført'
      WHEN 'lukket' THEN 'ferdig behandlet'
      ELSE new.status::text
    END;

    _title := 'Avvik ' || _status_no;
    _body :=
      _ref || ' «' || left(coalesce(new.title, ''), 80) || '» '
      || 'har status «' || _status_no || '».';

    PERFORM public.queue_push_to_profile_if_allowed(
      new.company_id,
      new.reported_by,
      _title,
      _body,
      'ticket',
      'tickets',
      new.id,
      'ticket_status',
      'Avvik status (push)',
      false,
      jsonb_build_object(
        'type', 'ticket_status',
        'reference_type', 'tickets',
        'reference_id', new.id::text,
        'status', new.status::text
      )
    );

    SELECT email INTO _email
    FROM public.profiles
    WHERE id = new.reported_by;

    IF coalesce(_email, '') <> '' THEN
      PERFORM public.queue_email_if_allowed(
        new.company_id,
        new.reported_by,
        _email,
        _title,
        _body,
        'ticket',
        'tickets',
        new.id,
        'ticket_status',
        'Avvik status (e-post)',
        false
      );
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_ticket_reporter_channels ON public.tickets;
CREATE TRIGGER trg_notify_ticket_reporter_channels
  AFTER UPDATE OF status ON public.tickets
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_ticket_reporter_channels();

CREATE OR REPLACE FUNCTION public.profile_can_configure_notification_event(
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
  v_role public.user_role;
  v_broad BOOLEAN;
  v_scope TEXT;
  v_active BOOLEAN;
BEGIN
  SELECT p.role INTO v_role
  FROM public.profiles p
  WHERE p.id = p_profile_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  SELECT d.scope, d.is_active INTO v_scope, v_active
  FROM public.notification_event_definitions d
  WHERE d.id = p_event_id;

  IF NOT FOUND OR NOT coalesce(v_active, false) OR v_scope <> 'mavi' THEN
    RETURN false;
  END IF;

  v_broad := v_role IN (
    'leder'::public.user_role,
    'admin'::public.user_role,
    'superadmin'::public.user_role
  )
  OR public.profile_is_registered_department_leader(p_profile_id)
  OR EXISTS (
    SELECT 1
    FROM public.profiles pr
    WHERE pr.id = p_profile_id
      AND pr.employee_number IN ('100', '144', '25')
  );

  IF v_broad THEN
    RETURN true;
  END IF;

  RETURN p_event_id IN ('absence_decision', 'ticket_status');
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_notification_preferences()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_role public.user_role;
  v_broad BOOLEAN;
  v_events JSONB;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT p.role INTO v_role
  FROM public.profiles p
  WHERE p.id = v_uid;

  v_broad := v_role IN (
    'leder'::public.user_role,
    'admin'::public.user_role,
    'superadmin'::public.user_role
  )
  OR public.profile_is_registered_department_leader(v_uid)
  OR EXISTS (
    SELECT 1
    FROM public.profiles pr
    WHERE pr.id = v_uid
      AND pr.employee_number IN ('100', '144', '25')
  );

  SELECT coalesce(jsonb_agg(row_to_json(x)::jsonb ORDER BY x.sort_order, x.title), '[]'::jsonb)
  INTO v_events
  FROM (
    SELECT
      d.id,
      d.title,
      d.subtitle,
      d.category_group AS category,
      d.sort_order,
      CASE
        WHEN s.event_id IS NOT NULL THEN coalesce(s.sms_enabled, true)
        WHEN public.user_effective_notify_channel(v_uid) IN (
          'none'::public.notification_channel,
          'email'::public.notification_channel
        ) THEN false
        ELSE true
      END AS sms,
      CASE
        WHEN s.event_id IS NOT NULL THEN coalesce(s.email_enabled, true)
        WHEN public.user_effective_notify_channel(v_uid) IN (
          'none'::public.notification_channel,
          'sms'::public.notification_channel
        ) THEN false
        ELSE true
      END AS email,
      CASE
        WHEN s.event_id IS NOT NULL THEN coalesce(s.push_enabled, true)
        WHEN public.user_effective_notify_channel(v_uid) = 'none'::public.notification_channel
          THEN false
        ELSE true
      END AS push
    FROM public.notification_event_definitions d
    LEFT JOIN public.profile_notification_subscriptions s
      ON s.profile_id = v_uid AND s.event_id = d.id
    WHERE d.is_active = true
      AND d.scope = 'mavi'
      AND (
        v_broad
        OR d.id IN ('absence_decision', 'ticket_status')
      )
  ) x;

  RETURN jsonb_build_object(
    'is_manager', v_broad,
    'events', v_events
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.set_my_notification_preference(
  p_event_id TEXT,
  p_sms BOOLEAN,
  p_email BOOLEAN,
  p_push BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_company UUID;
  v_on BOOLEAN;
  v_channel public.notification_channel;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  IF NOT public.profile_can_configure_notification_event(v_uid, p_event_id) THEN
    RAISE EXCEPTION 'Du kan ikke endre dette varslet';
  END IF;

  SELECT company_id INTO v_company FROM public.profiles WHERE id = v_uid;

  v_on := coalesce(p_sms, false) OR coalesce(p_email, false) OR coalesce(p_push, false);
  v_channel := CASE
    WHEN coalesce(p_sms, false) AND coalesce(p_email, false) THEN 'both'::public.notification_channel
    WHEN coalesce(p_sms, false) THEN 'sms'::public.notification_channel
    WHEN coalesce(p_email, false) THEN 'email'::public.notification_channel
    ELSE 'none'::public.notification_channel
  END;

  INSERT INTO public.profile_notification_subscriptions (
    company_id, profile_id, event_id, subscribed, channel,
    sms_enabled, email_enabled, push_enabled, updated_at, updated_by
  )
  VALUES (
    v_company, v_uid, p_event_id, v_on, v_channel,
    coalesce(p_sms, false), coalesce(p_email, false), coalesce(p_push, false),
    now(), v_uid
  )
  ON CONFLICT (profile_id, event_id) DO UPDATE SET
    subscribed = EXCLUDED.subscribed,
    channel = EXCLUDED.channel,
    sms_enabled = EXCLUDED.sms_enabled,
    email_enabled = EXCLUDED.email_enabled,
    push_enabled = EXCLUDED.push_enabled,
    updated_at = now(),
    updated_by = v_uid;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_my_notification_preset(
  p_sms BOOLEAN,
  p_email BOOLEAN,
  p_push BOOLEAN
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  r RECORD;
  n INT := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  FOR r IN
    SELECT d.id
    FROM public.notification_event_definitions d
    WHERE d.is_active = true
      AND d.scope = 'mavi'
      AND public.profile_can_configure_notification_event(v_uid, d.id)
  LOOP
    PERFORM public.set_my_notification_preference(r.id, p_sms, p_email, p_push);
    n := n + 1;
  END LOOP;

  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.profile_personal_channel_on(UUID, TEXT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.profile_has_personal_channel_row(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.profile_can_configure_notification_event(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_notification_preferences() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_my_notification_preference(TEXT, BOOLEAN, BOOLEAN, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_my_notification_preset(BOOLEAN, BOOLEAN, BOOLEAN) TO authenticated;
