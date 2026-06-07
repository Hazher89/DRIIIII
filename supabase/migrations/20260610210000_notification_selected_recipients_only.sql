-- Varsler KUN til eksplisitt valgte mottakere — aldri masseutsendelse til ledere/admin.

-- ── Avvik: kun valgt saksbehandler (assigned_to) ─────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_leaders_on_ticket()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  reporter_name text;
  assignee_phone text;
  assignee_email text;
  assignee_name text;
  sms_body text;
  ref text;
BEGIN
  IF new.assigned_to IS NULL THEN
    RETURN new;
  END IF;

  IF NOT public.profile_receives_notification_event(
    new.company_id, new.assigned_to, 'ticket_assigned'
  ) THEN
    RETURN new;
  END IF;

  ref := public.ticket_public_ref(new.ticket_number);

  SELECT coalesce(full_name, 'Ansatt') INTO reporter_name
  FROM public.profiles WHERE id = new.reported_by;

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
END;
$$;

-- ── Fravær ved ny søknad: ingen massevarsling (kun ved beslutning senere) ─────
CREATE OR REPLACE FUNCTION public.notify_leaders_on_absence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN new;
END;
$$;

-- ── HMS: slå av «varsle nærmeste leder / alle admin» ─────────────────────────
CREATE OR REPLACE FUNCTION public.hms_notify_nearest_leaders(
  p_company_id uuid,
  p_department_id uuid,
  p_reporter_id uuid,
  p_title text,
  p_category text,
  p_reference_type text,
  p_reference_id uuid,
  p_setting_key text DEFAULT 'general'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Deaktivert: varsler sendes kun til eksplisitt valgte mottakere i appen.
  RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION public.hms_notify_on_ticket_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.hms_notify_on_risk_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.hms_notify_on_sja_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN NEW;
END;
$$;

-- ── ROS ↔ avvik: oppdater flagg i app — INGEN SMS/e-post til ledere/admin ───
CREATE OR REPLACE FUNCTION public.hms_process_avvik_ros_signal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_category text;
  v_count int;
  v_sample_ids uuid[];
  v_signal_id uuid;
BEGIN
  v_category := nullif(trim(coalesce(NEW.category, '')), '');
  IF v_category IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT count(*), array_agg(id ORDER BY created_at DESC)
  INTO v_count, v_sample_ids
  FROM public.tickets t
  WHERE t.company_id = NEW.company_id
    AND lower(trim(t.category)) = lower(v_category)
    AND t.created_at >= (now() - interval '30 days')
    AND t.status <> 'lukket'::public.ticket_status;

  IF v_count < 3 THEN
    RETURN NEW;
  END IF;

  UPDATE public.hms_ros_avvik_signals sig
  SET
    ticket_count = v_count,
    sample_ticket_ids = coalesce(v_sample_ids[1:5], '{}'),
    department_id = NEW.department_id,
    updated_at = now()
  WHERE sig.company_id = NEW.company_id
    AND lower(sig.ticket_category) = lower(v_category)
    AND sig.status = 'active'
  RETURNING sig.id INTO v_signal_id;

  IF v_signal_id IS NULL THEN
    INSERT INTO public.hms_ros_avvik_signals (
      company_id,
      department_id,
      ticket_category,
      ticket_count,
      sample_ticket_ids,
      status
    )
    VALUES (
      NEW.company_id,
      NEW.department_id,
      v_category,
      v_count,
      coalesce(v_sample_ids[1:5], '{}'),
      'active'
    )
    RETURNING id INTO v_signal_id;
  END IF;

  UPDATE public.risk_assessments ra
  SET
    avvik_boosted = true,
    avvik_signal_count = v_count,
    avvik_last_signal_at = now(),
    linked_ticket_category = v_category,
    initial_probability = LEAST(5, coalesce(ra.initial_probability, ra.probability) + 1),
    updated_at = now()
  WHERE ra.company_id = NEW.company_id
    AND ra.status = 'aktiv'
    AND (
      lower(coalesce(ra.linked_ticket_category, '')) = lower(v_category)
      OR lower(coalesce(ra.scenario_category, '')) = lower(v_category)
      OR lower(ra.title) LIKE '%' || lower(v_category) || '%'
    );

  RETURN NEW;
END;
$$;

-- SJA utløpt: kun ansvarlig person hvis satt — ikke avdelingsledere/admin
CREATE OR REPLACE FUNCTION public.hms_expire_overdue_sja()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec record;
BEGIN
  FOR rec IN
    SELECT s.*
    FROM public.sja_forms s
    WHERE s.status = 'i_gang'::public.sja_status
      AND s.valid_until IS NOT NULL
      AND s.valid_until < now()
      AND s.expired_notified_at IS NULL
  LOOP
    UPDATE public.sja_forms
    SET
      status = 'utlopt'::public.sja_status,
      expired_notified_at = now(),
      updated_at = now()
    WHERE id = rec.id;

    IF rec.responsible_person IS NOT NULL THEN
      PERFORM public.hms_notify_assigned_responsible(
        rec.company_id,
        rec.responsible_person,
        rec.title,
        'SJA utløpt — ny vurdering kreves',
        'sja_forms',
        rec.id,
        'hms_sja_expired',
        rec.created_by
      );
    END IF;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.notify_leaders_on_ticket IS
  'Avvik: SMS/e-post kun til valgt saksbehandler (assigned_to).';
COMMENT ON FUNCTION public.hms_process_avvik_ros_signal IS
  'ROS-avviksterskel: oppdaterer flagg i app — sender ikke SMS/e-post automatisk.';
