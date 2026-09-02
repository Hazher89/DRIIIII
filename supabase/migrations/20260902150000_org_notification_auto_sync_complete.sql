-- Automatisk org/leder-synk + 100 % avdelingsvarsler (fravær, avvik) og admin/leder-tilgang.
-- Løser: nye avdelinger/ansatte/ledere skal fungere uten manuell DB-justering.

-- ── 1. Felles leder-sjekk (brukes overalt) ───────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_department_leader_of(p_department_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.profile_leads_department(auth.uid(), p_department_id);
$$;

CREATE OR REPLACE FUNCTION public.profile_is_registered_department_leader(p_profile_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.department_leaders dl
    WHERE dl.profile_id = p_profile_id
  )
  OR EXISTS (
    SELECT 1
    FROM public.departments d
    WHERE d.leader_id = p_profile_id
  )
  OR EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = p_profile_id
      AND p.role = 'leder'::public.user_role
      AND p.department_id IS NOT NULL
      AND p.is_active = true
      AND p.is_approved = true
  );
$$;

-- ── 2. Auto-registrer avdelingsleder ved profil-/avdelingsendring ────────────

CREATE OR REPLACE FUNCTION public.ensure_profile_department_leadership(
  p_profile_id uuid,
  p_department_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_profile_id IS NULL OR p_department_id IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.department_leaders (department_id, profile_id)
  VALUES (p_department_id, p_profile_id)
  ON CONFLICT DO NOTHING;

  UPDATE public.departments d
  SET leader_id = COALESCE(d.leader_id, p_profile_id)
  FROM public.profiles p
  WHERE d.id = p_department_id
    AND p.id = p_profile_id
    AND d.company_id = p.company_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_profile_leadership_on_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.is_active IS NOT FALSE
     AND NEW.is_approved IS NOT FALSE
     AND NEW.department_id IS NOT NULL
     AND NEW.role = 'leder'::public.user_role THEN
    PERFORM public.ensure_profile_department_leadership(NEW.id, NEW.department_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_profile_leadership ON public.profiles;
CREATE TRIGGER trg_sync_profile_leadership
  AFTER INSERT OR UPDATE OF role, department_id, is_active, is_approved
  ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_profile_leadership_on_change();

-- Backfill alle godkjente ledere
INSERT INTO public.department_leaders (department_id, profile_id)
SELECT p.department_id, p.id
FROM public.profiles p
WHERE p.department_id IS NOT NULL
  AND p.role = 'leder'::public.user_role
  AND p.is_active = true
  AND p.is_approved = true
ON CONFLICT DO NOTHING;

-- ── 3. Synk avdeling på avvik fra innsender ──────────────────────────────────

CREATE OR REPLACE FUNCTION public.sync_ticket_department_from_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _dept uuid;
BEGIN
  IF NEW.reported_by IS NOT NULL THEN
    SELECT department_id INTO _dept
    FROM public.profiles
    WHERE id = NEW.reported_by;

    NEW.department_id := COALESCE(NEW.department_id, _dept);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_ticket_department ON public.tickets;
CREATE TRIGGER trg_sync_ticket_department
  BEFORE INSERT OR UPDATE OF reported_by ON public.tickets
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_ticket_department_from_profile();

UPDATE public.tickets t
SET department_id = p.department_id
FROM public.profiles p
WHERE t.reported_by = p.id
  AND t.department_id IS NULL
  AND p.department_id IS NOT NULL;

UPDATE public.absences a
SET department_id = p.department_id
FROM public.profiles p
WHERE a.user_id = p.id
  AND a.department_id IS NULL
  AND p.department_id IS NOT NULL;

-- ── 4. Datatilgang: admin ser alt, ledere ser avdelinger de leder ─────────────

CREATE OR REPLACE FUNCTION public.profile_in_my_data_scope(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p_user_id = auth.uid()
    OR (
      public.is_company_admin()
      AND EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = p_user_id
          AND p.company_id = public.get_user_company_id()
      )
    )
    OR EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = p_user_id
        AND p.company_id = public.get_user_company_id()
        AND p.department_id IS NOT NULL
        AND public.is_department_leader_of(p.department_id)
    );
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
  v_is_dept_leader boolean := false;
BEGIN
  SELECT * INTO p
  FROM public.profiles
  WHERE id = p_profile_id AND company_id = p_company_id;

  IF NOT FOUND OR NOT p.is_active OR NOT p.is_approved THEN
    RETURN false;
  END IF;

  v_is_dept_leader := public.profile_leads_department(p_profile_id, p_department_id);

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
      IF v_explicit = false
         AND v_is_dept_leader
         AND p_setting_key IN ('absence_request', 'ticket_new') THEN
        NULL;
      ELSE
        RETURN v_explicit;
      END IF;
    END IF;
  END IF;

  IF p.role IN ('admin'::public.user_role, 'superadmin'::public.user_role) THEN
    IF p_setting_key IN ('absence_request', 'ticket_new', 'ticket_assigned', 'ticket_status', 'ticket_critical') THEN
      RETURN true;
    END IF;
    IF v_event_id IS NULL THEN
      RETURN true;
    END IF;
    RETURN public.profile_default_event_subscription(p_company_id, p_profile_id, v_event_id);
  END IF;

  IF v_is_dept_leader THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

-- Fjern feilaktige avmeldinger for avdelingsledere på obligatoriske hendelser
DELETE FROM public.profile_notification_subscriptions s
WHERE s.event_id IN ('absence_request', 'ticket_new')
  AND s.subscribed = false
  AND public.profile_is_registered_department_leader(s.profile_id);

-- ── 5. Avvik: push + SMS + e-post til avdelingsledere ────────────────────────

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
BEGIN
  IF tg_op <> 'INSERT' THEN
    RETURN new;
  END IF;

  ref := public.ticket_display_ref(new.trace_ref, new.ticket_number);

  SELECT coalesce(full_name, 'Ansatt') INTO reporter_name
  FROM public.profiles WHERE id = new.reported_by;

  dept_id := coalesce(
    new.department_id,
    (SELECT department_id FROM public.profiles WHERE id = new.reported_by)
  );

  push_title := ref || ' registrert';
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
      'DriftPro: ' || ref || ' til deg. «'
      || left(coalesce(new.title, 'Uten tittel'), 50)
      || '». Alvor: ' || coalesce(new.severity::text, 'middels')
      || '. Fra: ' || reporter_name || '.';

    PERFORM public.queue_push_to_profile_if_allowed(
      new.company_id, new.assigned_to,
      ref || ' — handling kreves', push_body,
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

DROP TRIGGER IF EXISTS trg_notify_leaders_on_ticket ON public.tickets;
CREATE TRIGGER trg_notify_leaders_on_ticket
  AFTER INSERT ON public.tickets
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_leaders_on_ticket();

-- ── 6. RLS: ledere via is_department_leader_of (inkl. ansatt-rolle) ─────────

DROP POLICY IF EXISTS profiles_select_leader_department ON public.profiles;
CREATE POLICY profiles_select_leader_department ON public.profiles
  FOR SELECT TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      id = auth.uid()
      OR (
        department_id IS NOT NULL
        AND public.is_department_leader_of(department_id)
      )
    )
  );

DROP POLICY IF EXISTS tickets_select_scoped ON public.tickets;
CREATE POLICY tickets_select_scoped ON public.tickets
  FOR SELECT TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      public.is_company_admin()
      OR reported_by = auth.uid()
      OR assigned_to = auth.uid()
      OR public.is_department_leader_of(
        coalesce(
          department_id,
          (SELECT p.department_id FROM public.profiles p WHERE p.id = tickets.reported_by)
        )
      )
    )
  );

DROP POLICY IF EXISTS tickets_update_scoped ON public.tickets;
CREATE POLICY tickets_update_scoped ON public.tickets
  FOR UPDATE TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      reported_by = auth.uid()
      OR assigned_to = auth.uid()
      OR public.is_department_leader_of(
        coalesce(
          department_id,
          (SELECT p.department_id FROM public.profiles p WHERE p.id = tickets.reported_by)
        )
      )
      OR public.is_company_admin()
    )
  )
  WITH CHECK (company_id = public.get_user_company_id());

DROP POLICY IF EXISTS absences_insert_manager ON public.absences;
CREATE POLICY absences_insert_manager ON public.absences
  FOR INSERT TO authenticated
  WITH CHECK (
    company_id = public.get_user_company_id()
    AND user_id IS DISTINCT FROM auth.uid()
    AND public.profile_in_my_data_scope(user_id)
    AND (
      public.is_company_admin()
      OR public.is_department_leader_of(
        (SELECT p.department_id FROM public.profiles p WHERE p.id = user_id)
      )
    )
  );

DROP POLICY IF EXISTS absences_update_manager ON public.absences;
CREATE POLICY absences_update_manager ON public.absences
  FOR UPDATE TO authenticated
  USING (
    public.absence_visible(absences)
    AND user_id IS DISTINCT FROM auth.uid()
    AND (
      public.is_company_admin()
      OR public.is_department_leader_of(
        coalesce(
          absences.department_id,
          (SELECT p.department_id FROM public.profiles p WHERE p.id = absences.user_id)
        )
      )
    )
  )
  WITH CHECK (public.absence_visible(absences));

DROP POLICY IF EXISTS absences_delete_scoped ON public.absences;
CREATE POLICY absences_delete_scoped ON public.absences
  FOR DELETE TO authenticated
  USING (
    (user_id = auth.uid() AND status = 'ventende'::public.absence_status)
    OR (
      public.is_company_admin()
      AND company_id = public.get_user_company_id()
    )
    OR (
      public.is_department_leader_of(
        coalesce(
          absences.department_id,
          (SELECT p.department_id FROM public.profiles p WHERE p.id = absences.user_id)
        )
      )
      AND public.profile_in_my_data_scope(user_id)
      AND user_id IS DISTINCT FROM auth.uid()
    )
  );

DROP POLICY IF EXISTS absence_quotas_select_scoped ON public.absence_quotas;
CREATE POLICY absence_quotas_select_scoped ON public.absence_quotas
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR (
      public.is_company_admin()
      AND company_id = public.get_user_company_id()
    )
    OR (
      company_id = public.get_user_company_id()
      AND EXISTS (
        SELECT 1
        FROM public.profiles emp
        WHERE emp.id = absence_quotas.user_id
          AND emp.department_id IS NOT NULL
          AND public.is_department_leader_of(emp.department_id)
      )
    )
  );

DROP POLICY IF EXISTS absence_quotas_update_leader_dept ON public.absence_quotas;
CREATE POLICY absence_quotas_update_leader_dept ON public.absence_quotas
  FOR UPDATE TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND user_id IS DISTINCT FROM auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.profiles emp
      WHERE emp.id = absence_quotas.user_id
        AND emp.department_id IS NOT NULL
        AND public.is_department_leader_of(emp.department_id)
    )
  )
  WITH CHECK (
    company_id = public.get_user_company_id()
    AND user_id IS DISTINCT FROM auth.uid()
  );

-- ── 7. add_department_leader: alltid synk ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.add_department_leader(
  p_department_id UUID,
  p_profile_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.ensure_profile_department_leadership(p_profile_id, p_department_id);
END;
$$;

-- ── 8. Sikre varslingskanaler for alle selskap ──────────────────────────────

DO $$
DECLARE
  c RECORD;
BEGIN
  FOR c IN SELECT id FROM public.companies LOOP
    PERFORM public.ensure_notification_event_channels(c.id);
  END LOOP;
END $$;

UPDATE public.notification_event_definitions
SET default_recipient_rule = 'department_scoped'
WHERE id IN ('absence_request', 'ticket_new');

GRANT EXECUTE ON FUNCTION public.ensure_profile_department_leadership(uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.sync_profile_leadership_on_change IS
  'Auto-registrerer godkjente profiler med rolle leder som avdelingsleder.';
COMMENT ON FUNCTION public.notify_leaders_on_ticket IS
  'Nytt avvik: push/SMS/e-post til avdelingsledere (+ tildelt saksbehandler ved assigned_to).';
