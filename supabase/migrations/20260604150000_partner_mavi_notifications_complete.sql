-- Full varseldekning: alle partner-funksjoner + nye typer + MAVI intern oversikt.

-- ── Nye kanaler: samarbeid (til partnere) ───────────────────────────────────
ALTER TABLE public.company_partner_notification_settings
  ADD COLUMN IF NOT EXISTS ch_partner_document public.notification_channel NOT NULL DEFAULT 'both',
  ADD COLUMN IF NOT EXISTS ch_partner_document_folder public.notification_channel NOT NULL DEFAULT 'both',
  ADD COLUMN IF NOT EXISTS ch_partner_shared_routine public.notification_channel NOT NULL DEFAULT 'email',
  ADD COLUMN IF NOT EXISTS ch_partner_route_reminder public.notification_channel NOT NULL DEFAULT 'both',
  ADD COLUMN IF NOT EXISTS ch_partner_route_rejected public.notification_channel NOT NULL DEFAULT 'both',
  ADD COLUMN IF NOT EXISTS ch_partner_route_accepted public.notification_channel NOT NULL DEFAULT 'sms',
  ADD COLUMN IF NOT EXISTS ch_partner_weekly_summary public.notification_channel NOT NULL DEFAULT 'both',
  ADD COLUMN IF NOT EXISTS ch_partner_mass_route public.notification_channel NOT NULL DEFAULT 'both',
  ADD COLUMN IF NOT EXISTS ch_partner_vehicle_inactive public.notification_channel NOT NULL DEFAULT 'sms';

-- ── Nye kanaler: MAVI internt (om partnere/ruter/dokument) ───────────────────
ALTER TABLE public.company_sms_settings
  ADD COLUMN IF NOT EXISTS ch_partner_route_ack_internal public.notification_channel NOT NULL DEFAULT 'both',
  ADD COLUMN IF NOT EXISTS ch_partner_route_pending_internal public.notification_channel NOT NULL DEFAULT 'both',
  ADD COLUMN IF NOT EXISTS ch_partner_document_internal public.notification_channel NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS ch_sap_route_received public.notification_channel NOT NULL DEFAULT 'both',
  ADD COLUMN IF NOT EXISTS ch_partner_rental_internal public.notification_channel NOT NULL DEFAULT 'both',
  ADD COLUMN IF NOT EXISTS ch_partner_deactivated_internal public.notification_channel NOT NULL DEFAULT 'sms';

-- Purring: timer før første påminnelse (timer)
ALTER TABLE public.company_partner_notification_settings
  ADD COLUMN IF NOT EXISTS route_ack_reminder_hours INT NOT NULL DEFAULT 24;

-- ── Utvid kanal-oppslag ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.company_partner_notification_channel(
  p_company_id UUID,
  p_key TEXT
)
RETURNS public.notification_channel
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  s public.company_partner_notification_settings%ROWTYPE;
BEGIN
  SELECT * INTO s FROM public.company_partner_notification_settings WHERE company_id = p_company_id;
  IF NOT FOUND THEN
    RETURN 'both'::public.notification_channel;
  END IF;
  CASE p_key
    WHEN 'partner_route' THEN RETURN s.ch_partner_route;
    WHEN 'partner_route_owner' THEN RETURN s.ch_partner_route_owner;
    WHEN 'partner_meeting' THEN RETURN s.ch_partner_meeting;
    WHEN 'partner_portal' THEN RETURN s.ch_partner_portal;
    WHEN 'partner_compose' THEN RETURN s.ch_partner_compose;
    WHEN 'vehicle_rental' THEN RETURN s.ch_vehicle_rental;
    WHEN 'vehicle_rental_status' THEN RETURN s.ch_vehicle_rental_status;
    WHEN 'partner_document' THEN RETURN s.ch_partner_document;
    WHEN 'partner_document_folder' THEN RETURN s.ch_partner_document_folder;
    WHEN 'partner_shared_routine' THEN RETURN s.ch_partner_shared_routine;
    WHEN 'partner_route_reminder' THEN RETURN s.ch_partner_route_reminder;
    WHEN 'partner_route_rejected' THEN RETURN s.ch_partner_route_rejected;
    WHEN 'partner_route_accepted' THEN RETURN s.ch_partner_route_accepted;
    WHEN 'partner_weekly_summary' THEN RETURN s.ch_partner_weekly_summary;
    WHEN 'partner_mass_route' THEN RETURN s.ch_partner_mass_route;
    WHEN 'partner_vehicle_inactive' THEN RETURN s.ch_partner_vehicle_inactive;
    ELSE RETURN s.ch_partner_general;
  END CASE;
END;
$$;

CREATE OR REPLACE FUNCTION public.company_employee_notification_channel(
  p_company_id UUID,
  p_key TEXT
)
RETURNS public.notification_channel
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  s public.company_sms_settings%ROWTYPE;
  ch public.notification_channel;
BEGIN
  SELECT * INTO s FROM public.company_sms_settings WHERE company_id = p_company_id;
  IF NOT FOUND THEN
    RETURN 'both'::public.notification_channel;
  END IF;
  CASE p_key
    WHEN 'absence_request' THEN ch := s.ch_absence_request;
    WHEN 'absence_decision' THEN ch := s.ch_absence_decision;
    WHEN 'ticket_new' THEN ch := s.ch_ticket_new;
    WHEN 'ticket_status' THEN ch := s.ch_ticket_status;
    WHEN 'ticket_critical' THEN ch := s.ch_ticket_critical;
    WHEN 'equipment' THEN ch := s.ch_equipment;
    WHEN 'user_approval' THEN ch := s.ch_user_approval;
    WHEN 'partner_route_ack_internal' THEN ch := s.ch_partner_route_ack_internal;
    WHEN 'partner_route_pending_internal' THEN ch := s.ch_partner_route_pending_internal;
    WHEN 'partner_document_internal' THEN ch := s.ch_partner_document_internal;
    WHEN 'sap_route_received' THEN ch := s.ch_sap_route_received;
    WHEN 'partner_rental_internal' THEN ch := s.ch_partner_rental_internal;
    WHEN 'partner_deactivated_internal' THEN ch := s.ch_partner_deactivated_internal;
    ELSE ch := s.ch_general;
  END CASE;
  IF ch IS NULL THEN
    RETURN 'both'::public.notification_channel;
  END IF;
  RETURN ch;
END;
$$;

-- ── Partner e-post/SMS hjelpere ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.queue_partner_email_if_allowed(
  p_company_id UUID,
  p_to_email TEXT,
  p_subject TEXT,
  p_body TEXT,
  p_category TEXT,
  p_setting_key TEXT,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id UUID DEFAULT NULL,
  p_description TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.queue_email_if_allowed(
    p_company_id, NULL, p_to_email, p_subject, p_body,
    p_category, p_reference_type, p_reference_id,
    p_setting_key, p_description, true
  );
$$;

CREATE OR REPLACE FUNCTION public.notify_partner_owner_phones(
  p_company_id UUID,
  p_partner_id UUID,
  p_message TEXT,
  p_category TEXT,
  p_setting_key TEXT,
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
  sent TEXT[] := ARRAY[]::TEXT[];
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.partners p WHERE p.id = p_partner_id AND p.is_active = true) THEN
    RETURN 0;
  END IF;
  FOR rec IN SELECT pop.phone FROM public.partner_owner_sms_phones(p_partner_id) pop
  LOOP
    IF rec.phone IS NOT NULL AND NOT (rec.phone = ANY (sent)) THEN
      IF public.queue_partner_sms_if_allowed(
        p_company_id, rec.phone, p_message, p_category, p_setting_key,
        p_reference_type, p_reference_id, p_description
      ) IS NOT NULL THEN
        n := n + 1;
      END IF;
      sent := array_append(sent, rec.phone);
    END IF;
  END LOOP;
  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_partner_owner_emails(
  p_company_id UUID,
  p_partner_id UUID,
  p_subject TEXT,
  p_body TEXT,
  p_category TEXT,
  p_setting_key TEXT,
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
  sent TEXT[] := ARRAY[]::TEXT[];
  v_email TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.partners p WHERE p.id = p_partner_id AND p.is_active = true) THEN
    RETURN 0;
  END IF;
  FOR rec IN
    SELECT login_email AS email
    FROM public.partner_portal_accounts
    WHERE partner_id = p_partner_id AND is_active = true
      AND coalesce(login_email, '') <> ''
      AND coalesce(account_kind, 'owner') IN ('owner', 'admin')
  LOOP
    v_email := trim(lower(rec.email));
    IF v_email <> '' AND NOT (v_email = ANY (sent)) THEN
      IF public.queue_partner_email_if_allowed(
        p_company_id, v_email, p_subject, p_body, p_category,
        p_setting_key, p_reference_type, p_reference_id, p_description
      ) IS NOT NULL THEN
        n := n + 1;
      END IF;
      sent := array_append(sent, v_email);
    END IF;
  END LOOP;
  SELECT trim(lower(p.email)) INTO v_email FROM public.partners p WHERE p.id = p_partner_id;
  IF v_email IS NOT NULL AND v_email <> '' AND NOT (v_email = ANY (sent)) THEN
    IF public.queue_partner_email_if_allowed(
      p_company_id, v_email, p_subject, p_body, p_category,
      p_setting_key, p_reference_type, p_reference_id, p_description
    ) IS NOT NULL THEN
      n := n + 1;
    END IF;
  END IF;
  RETURN n;
END;
$$;

-- ── MAVI ledere (interne partner-varsler) ───────────────────────────────────
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
    SELECT id, email, phone_normalized, phone
    FROM public.profiles
    WHERE company_id = p_company_id
      AND role IN ('leder', 'admin', 'superadmin')
      AND is_active = true
      AND is_approved = true
  LOOP
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

-- ── Oppdaterte partner-RPC ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_partner_meeting_sms(
  p_partner_id UUID,
  p_message TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID;
BEGIN
  SELECT p.company_id INTO v_company
  FROM public.partners p WHERE p.id = p_partner_id AND p.is_active = true;
  IF v_company IS NULL THEN RETURN 0; END IF;
  RETURN public.notify_partner_owner_phones(
    v_company, p_partner_id, left(p_message, 1600),
    'partner_meeting', 'partner_meeting', 'partners', p_partner_id,
    'Møte / oppfølging'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_partner_portal_credentials_sms(
  p_company_id UUID,
  p_phone TEXT,
  p_username TEXT,
  p_password TEXT,
  p_is_owner BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  role_label TEXT := CASE WHEN p_is_owner THEN 'bil-eier' ELSE 'sjåfør' END;
  msg TEXT;
BEGIN
  msg := 'DriftPro ' || role_label || E'\nBruker: ' || p_username ||
    E'\nPassord: ' || p_password ||
    E'\nLogg inn: driftpro.no (Samarbeidspartner)';
  RETURN public.queue_partner_sms_if_allowed(
    p_company_id, p_phone, msg, 'partner_portal', 'partner_portal',
    'partner_portal_accounts', NULL, 'Portal-innlogging opprettet'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_partner_route_assigned_sms(p_route_share_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  shift_name TEXT;
  driver_msg TEXT;
  owner_msg TEXT;
  email_sub TEXT;
  email_body TEXT;
  n INT := 0;
  driver_phone TEXT;
  owner_rec RECORD;
  owner_only BOOLEAN;
  sent_phones TEXT[] := ARRAY[]::TEXT[];
BEGIN
  SELECT
    prs.*,
    pv.unit_code,
    pv.registration_number AS vehicle_reg,
    p.name AS partner_name,
    p.is_active AS partner_is_active,
    coalesce(p.routes_owner_only, true) AS routes_owner_only
  INTO r
  FROM public.partner_route_shares prs
  LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
  LEFT JOIN public.partners p ON p.id = prs.partner_id
  WHERE prs.id = p_route_share_id;

  IF r IS NULL OR coalesce(r.partner_is_active, false) = false THEN
    RETURN 0;
  END IF;
  IF r.partner_vehicle_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.partner_vehicles pv2
    WHERE pv2.id = r.partner_vehicle_id AND pv2.is_active = true
  ) THEN
    RETURN 0;
  END IF;
  IF coalesce(r.dispatch_status, 'sent') <> 'sent' THEN
    RETURN 0;
  END IF;

  owner_only := coalesce(r.routes_owner_only, true);
  SELECT name INTO shift_name FROM public.fleet_shift_definitions WHERE id = r.shift_id;

  driver_msg := 'Ny rute tildelt ' || coalesce(r.unit_code, '') ||
    CASE WHEN r.vehicle_reg IS NOT NULL AND trim(r.vehicle_reg) <> '' THEN ' (' || trim(r.vehicle_reg) || ')' ELSE '' END ||
    CASE WHEN shift_name IS NOT NULL THEN ' · Skift: ' || shift_name ELSE '' END ||
    '. Logg inn i DriftPro for PDF og aksept.';

  owner_msg := 'Ny rute på ' || coalesce(r.unit_code, 'bil') ||
    ' — ' || coalesce(r.partner_name, 'din bedrift') ||
    CASE WHEN shift_name IS NOT NULL THEN ' · ' || shift_name ELSE '' END ||
    '. Logg inn i DriftPro for oversikt og godkjenning.';

  email_sub := 'Ny rute i DriftPro';
  email_body := owner_msg || E'\n\nLogg inn på driftpro.no (Samarbeidspartner).';

  IF NOT owner_only THEN
    SELECT public.normalize_phone_no(ppa.phone) INTO driver_phone
    FROM public.partner_portal_accounts ppa
    JOIN public.partners p ON p.id = ppa.partner_id AND p.is_active = true
    WHERE ppa.partner_vehicle_id = r.partner_vehicle_id
      AND ppa.is_active = true
      AND coalesce(ppa.account_kind, 'driver') = 'driver'
      AND ppa.phone IS NOT NULL
    ORDER BY ppa.updated_at DESC NULLS LAST
    LIMIT 1;

    IF driver_phone IS NOT NULL AND NOT (driver_phone = ANY (sent_phones)) THEN
      IF public.queue_partner_sms_if_allowed(
        r.company_id, driver_phone, driver_msg, 'partner_route', 'partner_route',
        'partner_route_shares', r.id, 'Ny rute → sjåfør'
      ) IS NOT NULL THEN
        sent_phones := array_append(sent_phones, driver_phone);
        n := n + 1;
      END IF;
    END IF;
  END IF;

  n := n + public.notify_partner_owner_phones(
    r.company_id, r.partner_id, owner_msg, 'partner_route_owner', 'partner_route_owner',
    'partner_route_shares', r.id, 'Ny rute → bil-eier'
  );

  n := n + public.notify_partner_owner_emails(
    r.company_id, r.partner_id, email_sub, email_body, 'partner_route_share',
    'partner_route_owner', 'partner_route_shares', r.id, 'Ny rute (e-post)'
  );

  RETURN n;
END;
$$;

-- ── Dokument delt med partner ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_partner_document_shared(p_document_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d RECORD;
  msg TEXT;
  sub TEXT;
  body TEXT;
  n INT := 0;
BEGIN
  SELECT pd.*, p.name AS partner_name, p.company_id, p.is_active AS partner_active
  INTO d
  FROM public.partner_documents pd
  JOIN public.partners p ON p.id = pd.partner_id
  WHERE pd.id = p_document_id;

  IF d IS NULL OR NOT coalesce(d.partner_active, false) OR NOT coalesce(d.owner_visible, true) THEN
    RETURN 0;
  END IF;

  msg := 'Nytt dokument i DriftPro: «' || coalesce(d.title, 'Dokument') || '». Logg inn i bil-eier portalen.';
  sub := 'Nytt dokument: ' || coalesce(d.title, 'Dokument');
  body := msg || E'\n\nBedrift: ' || coalesce(d.partner_name, '');

  n := public.notify_partner_owner_phones(
    d.company_id, d.partner_id, msg, 'partner_document', 'partner_document',
    'partner_documents', d.id, 'Dokument delt'
  );
  n := n + public.notify_partner_owner_emails(
    d.company_id, d.partner_id, sub, body, 'partner_document', 'partner_document',
    'partner_documents', d.id, 'Dokument delt (e-post)'
  );

  PERFORM public.notify_mavi_partner_internal(
    d.company_id, 'partner_document_internal',
    sub, body, 'MAVI: ' || left(msg, 200),
    'partner_document_internal', 'partner_documents', d.id,
    'Internt: dokument lastet opp til partner'
  );

  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_partner_document_notify()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF coalesce(NEW.owner_visible, false) = true THEN
    PERFORM public.notify_partner_document_shared(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS partner_document_notify ON public.partner_documents;
CREATE TRIGGER partner_document_notify
  AFTER INSERT ON public.partner_documents
  FOR EACH ROW EXECUTE FUNCTION public.trg_partner_document_notify();

-- ── Rute kvittering / avslag → partner + MAVI ───────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_internal_on_route_ack()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  p_name TEXT;
  sms_txt TEXT;
  sub TEXT;
  body TEXT;
BEGIN
  IF TG_OP <> 'UPDATE' THEN RETURN NEW; END IF;
  IF coalesce(OLD.ack_status, 'pending') = coalesce(NEW.ack_status, 'pending') THEN
    RETURN NEW;
  END IF;

  SELECT name INTO p_name FROM public.partners WHERE id = NEW.partner_id;

  sub := 'Rute kvittering: ' || coalesce(p_name, 'Partner');
  body := 'Status: ' || NEW.ack_status || E'\nKommentar: ' || coalesce(NEW.ack_comment, '-');
  sms_txt := 'MAVI: ' || coalesce(p_name, 'Partner') || ' har ' || NEW.ack_status || ' rute.';

  PERFORM public.notify_mavi_partner_internal(
    NEW.company_id, 'partner_route_ack_internal',
    sub, body, sms_txt, 'partner_route_ack', 'partner_route_shares', NEW.id,
    'Partner kvitterte rute'
  );

  IF NEW.ack_status = 'rejected' THEN
    PERFORM public.notify_partner_owner_phones(
      NEW.company_id, NEW.partner_id,
      'Bekreftelse: ruten er registrert som avvist i DriftPro. Kontakt MAVI ved spørsmål.',
      'partner_route_rejected', 'partner_route_rejected',
      'partner_route_shares', NEW.id, 'Rute avvist (bekreftelse)'
    );
  ELSIF NEW.ack_status = 'accepted' THEN
    PERFORM public.notify_partner_owner_phones(
      NEW.company_id, NEW.partner_id,
      'Takk! Ruten er godkjent i DriftPro.',
      'partner_route_accepted', 'partner_route_accepted',
      'partner_route_shares', NEW.id, 'Rute godkjent'
    );
  END IF;

  RETURN NEW;
END;
$$;

-- ── Purring: ruter uten aksept ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enqueue_partner_route_ack_reminders()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  hours INT;
  msg TEXT;
  n INT := 0;
BEGIN
  FOR rec IN
    SELECT prs.id, prs.company_id, prs.partner_id, prs.created_at,
           p.name AS partner_name, pv.unit_code
    FROM public.partner_route_shares prs
    JOIN public.partners p ON p.id = prs.partner_id AND p.is_active = true
    LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
    WHERE coalesce(prs.ack_status, 'pending') = 'pending'
      AND coalesce(prs.dispatch_status, 'sent') = 'sent'
      AND prs.sent_at IS NOT NULL
  LOOP
    SELECT coalesce(s.route_ack_reminder_hours, 24) INTO hours
    FROM public.company_partner_notification_settings s
    WHERE s.company_id = rec.company_id;
    hours := coalesce(hours, 24);

    IF rec.created_at > now() - (hours || ' hours')::interval THEN
      CONTINUE;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.sms_outbox o
      WHERE o.reference_id = rec.id
        AND o.category = 'partner_route_reminder'
        AND o.created_at > now() - interval '12 hours'
    ) THEN
      CONTINUE;
    END IF;

    msg := 'PÅMINNELSE: Rute ' || coalesce(rec.unit_code, '') ||
      ' venter på aksept i DriftPro. Logg inn og godkjenn eller avvis.';

    n := n + public.notify_partner_owner_phones(
      rec.company_id, rec.partner_id, msg, 'partner_route_reminder', 'partner_route_reminder',
      'partner_route_shares', rec.id, 'Purring rute uten aksept'
    );
    n := n + public.notify_partner_owner_emails(
      rec.company_id, rec.partner_id,
      'Påminnelse: rute venter på aksept',
      msg, 'partner_route_reminder', 'partner_route_reminder',
      'partner_route_shares', rec.id, 'Purring rute (e-post)'
    );
  END LOOP;
  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.enqueue_mavi_pending_routes_digest()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  cnt INT;
  sub TEXT;
  body TEXT;
  sms_txt TEXT;
  n INT := 0;
BEGIN
  FOR rec IN
    SELECT prs.company_id, count(*)::int AS pending_cnt
    FROM public.partner_route_shares prs
    JOIN public.partners p ON p.id = prs.partner_id AND p.is_active = true
    WHERE coalesce(prs.ack_status, 'pending') = 'pending'
      AND coalesce(prs.dispatch_status, 'sent') = 'sent'
      AND prs.created_at < now() - interval '6 hours'
    GROUP BY prs.company_id
    HAVING count(*) > 0
  LOOP
    cnt := rec.pending_cnt;
    sub := 'MAVI: ' || cnt || ' ruter venter på partner-aksept';
    body := 'Det finnes ' || cnt || ' rute(r) som samarbeidspartnere ikke har akseptert ennå. Sjekk ruteplanlegger i DriftPro.';
    sms_txt := sub;

    n := n + public.notify_mavi_partner_internal(
      rec.company_id, 'partner_route_pending_internal',
      sub, body, sms_txt, 'partner_route_pending', NULL, NULL,
      'Internt: ventende rute-aksept'
    );
  END LOOP;
  RETURN n;
END;
$$;

-- ── SAP innboks ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_sap_route_inbox_received()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  sub TEXT;
  body TEXT;
BEGIN
  IF NEW.status IS DISTINCT FROM 'pending' THEN
    RETURN NEW;
  END IF;
  sub := 'SAP: ny rute-PDF mottatt';
  body := 'Fil: ' || coalesce(NEW.file_name, 'PDF') || E'\nImporter fra ruteplanlegger (SAP-knapp).';
  PERFORM public.notify_mavi_partner_internal(
    NEW.company_id, 'sap_route_received',
    sub, body, 'MAVI: Ny SAP rute-PDF. Importer i DriftPro.',
    'sap_inbox', 'sap_route_inbox', NEW.id, 'SAP Backup Form mottatt'
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sap_route_inbox_notify ON public.sap_route_inbox;
CREATE TRIGGER sap_route_inbox_notify
  AFTER INSERT ON public.sap_route_inbox
  FOR EACH ROW EXECUTE FUNCTION public.notify_sap_route_inbox_received();

-- ── Bilutleie (via setting keys) ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_vehicle_rental_partner_sms(
  p_rental_id UUID,
  p_event TEXT
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  borrower_name TEXT;
  msg TEXT;
  setting_key TEXT;
  cat TEXT;
  n INT := 0;
BEGIN
  SELECT vr.*, p.name AS lender_name, p.is_active AS lender_active
  INTO r
  FROM public.vehicle_rentals vr
  JOIN public.partners p ON p.id = vr.lender_partner_id
  WHERE vr.id = p_rental_id;

  IF r IS NULL OR NOT coalesce(r.lender_active, false) THEN RETURN 0; END IF;

  SELECT name INTO borrower_name FROM public.partners WHERE id = r.borrower_partner_id;

  CASE p_event
    WHEN 'created' THEN
      setting_key := 'vehicle_rental'; cat := 'vehicle_rental';
      msg := 'Ny bilutleie-forespørsel fra ' || coalesce(borrower_name, 'partner') || '. Åpne DriftPro.';
    WHEN 'approved' THEN
      setting_key := 'vehicle_rental_status'; cat := 'vehicle_rental_status';
      msg := 'Bilutleie godkjent. Se detaljer i DriftPro.';
    WHEN 'rejected' THEN
      setting_key := 'vehicle_rental_status'; cat := 'vehicle_rental_status';
      msg := 'Bilutleie avvist. Se DriftPro.';
    WHEN 'return_approved' THEN
      setting_key := 'vehicle_rental_status'; cat := 'vehicle_rental_status';
      msg := 'Retur av bilutleie godkjent.';
    WHEN 'return_due_2h' THEN
      setting_key := 'vehicle_rental_status'; cat := 'vehicle_rental_status';
      msg := 'PÅMINNELSE: Bilutleie skal returneres innen ca. 2 timer.';
    ELSE
      setting_key := 'partner_general'; cat := 'vehicle_rental';
      msg := 'Oppdatering bilutleie i DriftPro.';
  END CASE;

  n := public.notify_partner_owner_phones(
    r.company_id, r.lender_partner_id, msg, cat, setting_key,
    'vehicle_rentals', r.id, 'Bilutleie: ' || p_event
  );

  PERFORM public.notify_mavi_partner_internal(
    r.company_id, 'partner_rental_internal',
    'Bilutleie: ' || p_event, msg, 'MAVI bilutleie ' || p_event,
    cat, 'vehicle_rentals', r.id, 'Internt bilutleie'
  );

  RETURN n;
END;
$$;

-- Cron purring (hvis pg_cron)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN PERFORM cron.unschedule('partner-route-ack-reminder'); EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM cron.unschedule('mavi-pending-routes-digest'); EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM cron.schedule(
      'partner-route-ack-reminder',
      '0 */6 * * *',
      $cron$SELECT public.enqueue_partner_route_ack_reminders();$cron$
    );
    PERFORM cron.schedule(
      'mavi-pending-routes-digest',
      '0 7 * * *',
      $cron$SELECT public.enqueue_mavi_pending_routes_digest();$cron$
    );
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_partner_document_shared(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.enqueue_partner_route_ack_reminders() TO service_role;
GRANT EXECUTE ON FUNCTION public.enqueue_mavi_pending_routes_digest() TO service_role;

-- E-post partner scope filter
CREATE OR REPLACE FUNCTION public.is_partner_scope_email_category(p_category TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(p_category, '') IN (
    'partner_route', 'partner_route_owner', 'partner_meeting', 'partner_portal',
    'partner_compose', 'vehicle_rental', 'vehicle_rental_status', 'partner_route_share',
    'partner_route_ack', 'partner_document', 'partner_route_reminder',
    'partner_route_rejected', 'partner_route_accepted', 'partner_document_internal',
    'partner_route_pending', 'sap_inbox', 'partner_document_internal'
  ) OR COALESCE(p_category, '') LIKE 'partner%'
     OR COALESCE(p_category, '') LIKE 'vehicle_rental%';
$$;
