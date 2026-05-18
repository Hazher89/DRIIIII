-- Smart SMS (Mavi-avsender via SVEVE_FROM) + firmainnstillinger + fravær-ruting
-- Kjør etter sms_outbox_sveve.sql. Sett SVEVE_FROM = 'Mavi' (maks 11 tegn).

-- Normalisert telefon for Sveve
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS phone_normalized TEXT,
  ADD COLUMN IF NOT EXISTS sms_opt_in BOOLEAN NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.profiles_sync_phone_normalized()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.phone_normalized := public.normalize_phone_no(NEW.phone);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_phone_normalized ON public.profiles;
CREATE TRIGGER trg_profiles_phone_normalized
  BEFORE INSERT OR UPDATE OF phone ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.profiles_sync_phone_normalized();

UPDATE public.profiles SET phone = phone WHERE phone IS NOT NULL;

-- Firmavide SMS-brytere (default PÅ)
CREATE TABLE IF NOT EXISTS public.company_sms_settings (
  company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  sms_absence_request BOOLEAN NOT NULL DEFAULT true,
  sms_absence_decision BOOLEAN NOT NULL DEFAULT true,
  sms_ticket_new BOOLEAN NOT NULL DEFAULT true,
  sms_ticket_status BOOLEAN NOT NULL DEFAULT true,
  sms_ticket_critical BOOLEAN NOT NULL DEFAULT true,
  sms_equipment BOOLEAN NOT NULL DEFAULT true,
  sms_general BOOLEAN NOT NULL DEFAULT true,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

ALTER TABLE public.company_sms_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "company_sms_settings_co" ON public.company_sms_settings;
CREATE POLICY "company_sms_settings_co" ON public.company_sms_settings
  FOR ALL
  USING (company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid()))
  WITH CHECK (company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid()));

CREATE OR REPLACE FUNCTION public.company_sms_enabled(p_company_id UUID, p_key TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  s public.company_sms_settings%ROWTYPE;
BEGIN
  SELECT * INTO s FROM public.company_sms_settings WHERE company_id = p_company_id;
  IF NOT FOUND THEN
    RETURN true;
  END IF;
  CASE p_key
    WHEN 'absence_request' THEN RETURN s.sms_absence_request;
    WHEN 'absence_decision' THEN RETURN s.sms_absence_decision;
    WHEN 'ticket_new' THEN RETURN s.sms_ticket_new;
    WHEN 'ticket_status' THEN RETURN s.sms_ticket_status;
    WHEN 'ticket_critical' THEN RETURN s.sms_ticket_critical;
    WHEN 'equipment' THEN RETURN s.sms_equipment;
    ELSE RETURN s.sms_general;
  END CASE;
END;
$$;

CREATE OR REPLACE FUNCTION public.user_accepts_sms(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT sms_opt_in FROM public.profiles WHERE id = p_user_id),
    true
  );
$$;

CREATE OR REPLACE FUNCTION public.queue_sms_if_allowed(
  p_company_id UUID,
  p_user_id UUID,
  p_phone TEXT,
  p_message TEXT,
  p_category TEXT,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id UUID DEFAULT NULL,
  p_setting_key TEXT DEFAULT 'general'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.company_sms_enabled(p_company_id, p_setting_key) THEN
    RETURN;
  END IF;
  IF p_user_id IS NOT NULL AND NOT public.user_accepts_sms(p_user_id) THEN
    RETURN;
  END IF;
  PERFORM public.queue_sms(
    p_company_id,
    COALESCE(
      (SELECT phone_normalized FROM public.profiles WHERE id = p_user_id),
      p_phone
    ),
    p_message,
    p_category,
    p_reference_type,
    p_reference_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.queue_sms_if_allowed TO authenticated, service_role;

-- Mottakere for nytt fravær: avdelingsleder, eller superadmin hvis leder har godkjent ferie/fravær
CREATE OR REPLACE FUNCTION public.queue_absence_request_sms(p_absence public.absences)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  emp_name TEXT;
  dept_name TEXT;
  leader_id UUID;
  leader_on_leave BOOLEAN := false;
  msg TEXT;
  type_label TEXT;
BEGIN
  IF NOT public.company_sms_enabled(p_absence.company_id, 'absence_request') THEN
    RETURN;
  END IF;

  SELECT COALESCE(full_name, 'Ansatt') INTO emp_name
  FROM public.profiles WHERE id = p_absence.user_id;

  SELECT d.name, d.leader_id INTO dept_name, leader_id
  FROM public.departments d
  WHERE d.id = p_absence.department_id;

  type_label := CASE p_absence.type::text
    WHEN 'ferie' THEN 'ferie'
    WHEN 'sykdom' THEN 'sykmelding/fravær'
    WHEN 'permisjon' THEN 'permisjon'
    ELSE COALESCE(p_absence.type::text, 'fravær')
  END;

  msg :=
    'Mavi: NY SØKNAD ' || upper(type_label) || '. '
    || emp_name
    || ' (' || COALESCE(dept_name, 'uten avdeling') || ') '
    || to_char(p_absence.start_date, 'DD.MM') || '-' || to_char(p_absence.end_date, 'DD.MM')
    || '. Status: venter godkjenning. Åpne DriftPro.';

  IF leader_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM public.absences a
      WHERE a.user_id = leader_id
        AND a.status = 'godkjent'
        AND a.start_date <= CURRENT_DATE
        AND a.end_date >= CURRENT_DATE
    ) INTO leader_on_leave;
  END IF;

  IF leader_id IS NOT NULL AND NOT leader_on_leave THEN
    PERFORM public.queue_sms_if_allowed(
      p_absence.company_id,
      leader_id,
      NULL,
      msg,
      'absence_request',
      'absences',
      p_absence.id,
      'absence_request'
    );
  ELSE
    FOR leader_id IN
      SELECT id FROM public.profiles
      WHERE company_id = p_absence.company_id
        AND is_active = true
        AND is_approved = true
        AND role IN ('superadmin', 'admin')
        AND phone_normalized IS NOT NULL
    LOOP
      PERFORM public.queue_sms_if_allowed(
        p_absence.company_id,
        leader_id,
        NULL,
        CASE WHEN leader_on_leave THEN
          'Mavi: LEDER PÅ FERIE/FRAVÆR – ' || msg
        ELSE
          msg
        END,
        'absence_request',
        'absences',
        p_absence.id,
        'absence_request'
      );
    END LOOP;
  END IF;
END;
$$;

-- Oppdater fravær-varsel
CREATE OR REPLACE FUNCTION public.notify_leaders_on_absence()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.queue_absence_request_sms(NEW);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_leaders_on_absence ON public.absences;
CREATE TRIGGER trg_notify_leaders_on_absence
  AFTER INSERT ON public.absences
  FOR EACH ROW EXECUTE FUNCTION public.notify_leaders_on_absence();

-- Godkjent/avvist → ansatt
CREATE OR REPLACE FUNCTION public.notify_absence_decision_sms()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _msg TEXT;
  decision TEXT;
BEGIN
  IF tg_op <> 'UPDATE' OR old.status <> 'ventende'
    OR new.status NOT IN ('godkjent', 'avvist') THEN
    RETURN NEW;
  END IF;

  decision := CASE WHEN new.status = 'godkjent' THEN 'GODKJENT' ELSE 'AVVIST' END;

  _msg :=
    'Mavi: FRAVÆR ' || decision || '. '
    || 'Type: ' || COALESCE(new.type::text, 'fravær')
    || '. Periode: ' || to_char(new.start_date, 'DD.MM')
    || '-' || to_char(new.end_date, 'DD.MM')
    || '. Se detaljer i DriftPro.';

  PERFORM public.queue_sms_if_allowed(
    new.company_id,
    new.user_id,
    NULL,
    _msg,
    'absence_decision',
    'absences',
    new.id,
    'absence_decision'
  );

  RETURN NEW;
END;
$$;

-- Avvik – smartere tekst
CREATE OR REPLACE FUNCTION public.notify_leaders_on_ticket()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  reporter_name TEXT;
  sms_body TEXT;
BEGIN
  IF NOT public.company_sms_enabled(new.company_id, 'ticket_new') THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(full_name, 'Ansatt') INTO reporter_name
  FROM public.profiles WHERE id = new.reported_by;

  sms_body :=
    'Mavi: NYTT AVVIK. '
    || COALESCE(new.title, 'Uten tittel')
    || '. Alvorlighet: ' || COALESCE(new.severity::text, 'middels')
    || '. Meldt av: ' || reporter_name
    || '. Behandle i DriftPro.';

  FOR rec IN
    SELECT email
    FROM public.profiles
    WHERE company_id = new.company_id
      AND role IN ('leder', 'admin', 'superadmin')
      AND is_active = true
      AND coalesce(email, '') <> ''
  LOOP
    PERFORM public.queue_email(
      new.company_id,
      rec.email,
      'Nytt avvik registrert',
      'Tittel: ' || coalesce(new.title, 'uten tittel'),
      'ticket',
      'tickets',
      new.id
    );
  END LOOP;

  FOR rec IN
    SELECT id, phone_normalized, phone
    FROM public.profiles
    WHERE company_id = new.company_id
      AND role IN ('leder', 'admin', 'superadmin')
      AND is_active = true
      AND is_approved = true
      AND (
        role IN ('admin', 'superadmin')
        OR (role = 'leder' AND department_id IS NOT DISTINCT FROM new.department_id)
      )
  LOOP
    PERFORM public.queue_sms_if_allowed(
      new.company_id,
      rec.id,
      rec.phone,
      sms_body,
      'ticket',
      'tickets',
      new.id,
      'ticket_new'
    );
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_ticket_status_sms()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _msg TEXT;
BEGIN
  IF tg_op <> 'UPDATE' OR old.status IS NOT DISTINCT FROM new.status THEN
    RETURN NEW;
  END IF;
  IF NOT public.company_sms_enabled(new.company_id, 'ticket_status') THEN
    RETURN NEW;
  END IF;

  _msg :=
    'Mavi: AVVIK OPPDATERT. '
    || '«' || left(COALESCE(new.title, ''), 35) || '» '
    || 'ny status: ' || COALESCE(new.status::text, '')
    || '. Logg inn i DriftPro.';

  PERFORM public.queue_sms_if_allowed(
    new.company_id,
    new.reported_by,
    NULL,
    _msg,
    'ticket_status',
    'tickets',
    new.id,
    'ticket_status'
  );

  IF new.severity IN ('hoy', 'kritisk') AND new.status = 'aapen'
     AND public.company_sms_enabled(new.company_id, 'ticket_critical') THEN
    PERFORM public.queue_sms_to_leaders(
      new.company_id,
      new.department_id,
      'Mavi: KRITISK AVVIK – ' || COALESCE(new.title, '') || '. Krever handling.',
      'ticket_critical',
      'tickets',
      new.id
    );
  END IF;

  RETURN NEW;
END;
$$;
