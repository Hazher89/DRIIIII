-- Komplett varselkatalog + HMS-kanaler + RPC for les/skriv (sanntid fra app).

ALTER TABLE public.company_sms_settings
  ADD COLUMN IF NOT EXISTS ch_ticket_assigned public.notification_channel NOT NULL DEFAULT 'both',
  ADD COLUMN IF NOT EXISTS ch_hms public.notification_channel NOT NULL DEFAULT 'both',
  ADD COLUMN IF NOT EXISTS ch_hms_risk_assigned public.notification_channel NOT NULL DEFAULT 'both',
  ADD COLUMN IF NOT EXISTS ch_hms_sja_assigned public.notification_channel NOT NULL DEFAULT 'both',
  ADD COLUMN IF NOT EXISTS ch_hms_ros_avvik_signal public.notification_channel NOT NULL DEFAULT 'both',
  ADD COLUMN IF NOT EXISTS ch_hms_sja_expired public.notification_channel NOT NULL DEFAULT 'both';

CREATE TABLE IF NOT EXISTS public.notification_event_definitions (
  id text PRIMARY KEY,
  scope text NOT NULL CHECK (scope IN ('mavi', 'partner')),
  settings_table text NOT NULL CHECK (settings_table IN ('company_sms_settings', 'company_partner_notification_settings')),
  column_name text NOT NULL,
  setting_key text NOT NULL,
  title text NOT NULL,
  subtitle text,
  category_group text NOT NULL,
  sort_order int NOT NULL DEFAULT 0,
  legacy_sms_column text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.notification_event_definitions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notification_event_definitions_read ON public.notification_event_definitions;
CREATE POLICY notification_event_definitions_read ON public.notification_event_definitions
  FOR SELECT TO authenticated
  USING (is_active = true);

GRANT SELECT ON public.notification_event_definitions TO authenticated;

INSERT INTO public.notification_event_definitions (
  id, scope, settings_table, column_name, setting_key, title, subtitle, category_group, sort_order, legacy_sms_column
) VALUES
  ('absence_request', 'mavi', 'company_sms_settings', 'ch_absence_request', 'absence_request', 'Ny fravær/ferie-søknad', 'Til avdelingsleder', 'Fravær & ferie', 10, 'sms_absence_request'),
  ('absence_decision', 'mavi', 'company_sms_settings', 'ch_absence_decision', 'absence_decision', 'Fravær godkjent/avvist', 'Til ansatt', 'Fravær & ferie', 20, 'sms_absence_decision'),
  ('ticket_new', 'mavi', 'company_sms_settings', 'ch_ticket_new', 'ticket_new', 'Nytt avvik uten valgt saksbehandler', 'Til nærmeste leder', 'Avvik (HMS)', 30, 'sms_ticket_new'),
  ('ticket_assigned', 'mavi', 'company_sms_settings', 'ch_ticket_assigned', 'ticket_assigned', 'Avvik tildelt saksbehandler', 'Til valgt leder/HR', 'Avvik (HMS)', 40, NULL),
  ('ticket_status', 'mavi', 'company_sms_settings', 'ch_ticket_status', 'ticket_status', 'Avvik statusendring', 'Til den som meldte inn', 'Avvik (HMS)', 50, 'sms_ticket_status'),
  ('ticket_critical', 'mavi', 'company_sms_settings', 'ch_ticket_critical', 'ticket_critical', 'Kritiske avvik', 'Høy alvorlighet — purring', 'Avvik (HMS)', 60, 'sms_ticket_critical'),
  ('hms_risk_assigned', 'mavi', 'company_sms_settings', 'ch_hms_risk_assigned', 'hms_risk_assigned', 'ROS tildelt ansvarlig', 'E-post/SMS til ansvarlig person', 'HMS — ROS & SJA', 70, NULL),
  ('hms_sja_assigned', 'mavi', 'company_sms_settings', 'ch_hms_sja_assigned', 'hms_sja_assigned', 'SJA tildelt ansvarlig', 'E-post/SMS til ansvarlig person', 'HMS — ROS & SJA', 80, NULL),
  ('hms_ros_avvik_signal', 'mavi', 'company_sms_settings', 'ch_hms_ros_avvik_signal', 'hms_ros_avvik_signal', 'ROS må revideres (3+ like avvik)', 'Til operasjonsleder', 'HMS — ROS & SJA', 90, NULL),
  ('hms_sja_expired', 'mavi', 'company_sms_settings', 'ch_hms_sja_expired', 'hms_sja_expired', 'SJA utløpt', 'Ny vurdering kreves', 'HMS — ROS & SJA', 100, NULL),
  ('hms_general', 'mavi', 'company_sms_settings', 'ch_hms', 'hms', 'Generelle HMS-varsler', 'Ny ROS/SJA uten ansvarlig', 'HMS — ROS & SJA', 110, NULL),
  ('equipment', 'mavi', 'company_sms_settings', 'ch_equipment', 'equipment', 'Utstyr / truck', 'Service, avvik, kompetanse', 'Utstyr & brukere', 120, 'sms_equipment'),
  ('user_approval', 'mavi', 'company_sms_settings', 'ch_user_approval', 'user_approval', 'Ny ansatt venter godkjenning', 'Til admin/leder', 'Utstyr & brukere', 130, 'sms_user_approval'),
  ('partner_route_ack_internal', 'mavi', 'company_sms_settings', 'ch_partner_route_ack_internal', 'partner_route_ack_internal', 'Partner avviste rute (intern)', 'Kun ved avvisning', 'Intern — samarbeid', 140, NULL),
  ('partner_route_pending_internal', 'mavi', 'company_sms_settings', 'ch_partner_route_pending_internal', 'partner_route_pending_internal', 'Ruter venter aksept (intern)', 'Daglig oppsummering', 'Intern — samarbeid', 150, NULL),
  ('sap_route_received', 'mavi', 'company_sms_settings', 'ch_sap_route_received', 'sap_route_received', 'SAP rute-PDF mottatt', 'Ny fil i SAP-innboks', 'Intern — samarbeid', 160, NULL),
  ('partner_rental_internal', 'mavi', 'company_sms_settings', 'ch_partner_rental_internal', 'partner_rental_internal', 'Bilutleie-hendelser (intern)', 'Til MAVI-ledere', 'Intern — samarbeid', 170, NULL),
  ('partner_document_internal', 'mavi', 'company_sms_settings', 'ch_partner_document_internal', 'partner_document_internal', 'Dokument lastet opp til partner', 'Valgfritt internt varsel', 'Intern — samarbeid', 180, NULL),
  ('partner_deactivated_internal', 'mavi', 'company_sms_settings', 'ch_partner_deactivated_internal', 'partner_deactivated_internal', 'Bedrift deaktivert', 'Til superadmin/admin', 'Intern — samarbeid', 190, NULL),
  ('general', 'mavi', 'company_sms_settings', 'ch_general', 'general', 'Øvrige varsler til ansatte', 'Fallback for ukjente typer', 'Annet', 200, 'sms_general'),
  ('partner_route', 'partner', 'company_partner_notification_settings', 'ch_partner_route', 'partner_route', 'Ny rute → sjåfør', 'SMS/e-post ved publisering', 'Ruter', 10, NULL),
  ('partner_route_owner', 'partner', 'company_partner_notification_settings', 'ch_partner_route_owner', 'partner_route_owner', 'Ny rute → bil-eier', 'Portal og SMS', 'Ruter', 20, NULL),
  ('partner_route_reminder', 'partner', 'company_partner_notification_settings', 'ch_partner_route_reminder', 'partner_route_reminder', 'Purring: rute ikke akseptert', 'Automatisk påminnelse', 'Ruter', 30, NULL),
  ('partner_route_rejected', 'partner', 'company_partner_notification_settings', 'ch_partner_route_rejected', 'partner_route_rejected', 'Rute avvist av partner', 'Til MAVI internt', 'Ruter', 40, NULL),
  ('partner_route_accepted', 'partner', 'company_partner_notification_settings', 'ch_partner_route_accepted', 'partner_route_accepted', 'Rute godkjent (bekreftelse)', 'Deaktivert som standard', 'Ruter', 50, NULL),
  ('partner_mass_route', 'partner', 'company_partner_notification_settings', 'ch_partner_mass_route', 'partner_mass_route', 'MASS / masseutsendelse ruter', 'Bulk-publisering', 'Ruter', 60, NULL),
  ('partner_document', 'partner', 'company_partner_notification_settings', 'ch_partner_document', 'partner_document', 'Nytt dokument delt', 'Opplasting til partner-mappe', 'Dokumenter & portal', 70, NULL),
  ('partner_document_folder', 'partner', 'company_partner_notification_settings', 'ch_partner_document_folder', 'partner_document_folder', 'Ny dokumentmappe', 'Til partner-brukere', 'Dokumenter & portal', 80, NULL),
  ('partner_shared_routine', 'partner', 'company_partner_notification_settings', 'ch_partner_shared_routine', 'partner_shared_routine', 'Felles rutine/prosedyre', 'Alle partnere', 'Dokumenter & portal', 90, NULL),
  ('partner_portal', 'partner', 'company_partner_notification_settings', 'ch_partner_portal', 'partner_portal', 'Portal bruker / passord', 'Innlogging og tilgang', 'Dokumenter & portal', 100, NULL),
  ('partner_weekly_summary', 'partner', 'company_partner_notification_settings', 'ch_partner_weekly_summary', 'partner_weekly_summary', 'Ukesoppsummering økonomi', 'Til partnere', 'Dokumenter & portal', 110, NULL),
  ('partner_meeting', 'partner', 'company_partner_notification_settings', 'ch_partner_meeting', 'partner_meeting', 'Møte / oppfølging', 'Manuell oppfølging', 'SMS-hub & bilutleie', 120, NULL),
  ('partner_compose', 'partner', 'company_partner_notification_settings', 'ch_partner_compose', 'partner_compose', 'Manuell SMS/e-post fra hub', 'Fra SMS-hub', 'SMS-hub & bilutleie', 130, NULL),
  ('vehicle_rental', 'partner', 'company_partner_notification_settings', 'ch_vehicle_rental', 'vehicle_rental', 'Bilutleie — ny forespørsel', 'Til låner', 'SMS-hub & bilutleie', 140, NULL),
  ('vehicle_rental_status', 'partner', 'company_partner_notification_settings', 'ch_vehicle_rental_status', 'vehicle_rental_status', 'Bilutleie — status / purring', 'Retur, godkjenning', 'SMS-hub & bilutleie', 150, NULL),
  ('partner_vehicle_inactive', 'partner', 'company_partner_notification_settings', 'ch_partner_vehicle_inactive', 'partner_vehicle_inactive', 'Bil deaktivert / endring', 'Til partner', 'SMS-hub & bilutleie', 160, NULL),
  ('partner_general', 'partner', 'company_partner_notification_settings', 'ch_partner_general', 'partner_general', 'Øvrig samarbeid', 'Fallback partnervarsler', 'Annet', 170, NULL)
ON CONFLICT (id) DO UPDATE SET
  title = EXCLUDED.title,
  subtitle = EXCLUDED.subtitle,
  category_group = EXCLUDED.category_group,
  sort_order = EXCLUDED.sort_order,
  setting_key = EXCLUDED.setting_key,
  is_active = true;

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
    WHEN 'ticket_assigned' THEN ch := s.ch_ticket_assigned;
    WHEN 'ticket_status' THEN ch := s.ch_ticket_status;
    WHEN 'ticket_critical' THEN ch := s.ch_ticket_critical;
    WHEN 'equipment' THEN ch := s.ch_equipment;
    WHEN 'user_approval' THEN ch := s.ch_user_approval;
    WHEN 'hms' THEN ch := s.ch_hms;
    WHEN 'hms_risk_assigned' THEN ch := s.ch_hms_risk_assigned;
    WHEN 'hms_sja_assigned' THEN ch := s.ch_hms_sja_assigned;
    WHEN 'hms_ros_avvik_signal' THEN ch := s.ch_hms_ros_avvik_signal;
    WHEN 'hms_sja_expired' THEN ch := s.ch_hms_sja_expired;
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

CREATE OR REPLACE FUNCTION public.get_company_notification_events(p_company_id uuid)
RETURNS TABLE (
  id text,
  scope text,
  setting_key text,
  title text,
  subtitle text,
  category_group text,
  sort_order int,
  channel public.notification_channel
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  mavi public.company_sms_settings%ROWTYPE;
  partner public.company_partner_notification_settings%ROWTYPE;
BEGIN
  IF p_company_id <> public.get_user_company_id() THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  SELECT * INTO mavi FROM public.company_sms_settings WHERE company_id = p_company_id;
  SELECT * INTO partner FROM public.company_partner_notification_settings WHERE company_id = p_company_id;

  RETURN QUERY
  SELECT
    d.id,
    d.scope,
    d.setting_key,
    d.title,
    d.subtitle,
    d.category_group,
    d.sort_order,
    CASE
      WHEN d.scope = 'mavi' THEN
        CASE d.column_name
          WHEN 'ch_absence_request' THEN COALESCE(mavi.ch_absence_request, 'both'::public.notification_channel)
          WHEN 'ch_absence_decision' THEN COALESCE(mavi.ch_absence_decision, 'both'::public.notification_channel)
          WHEN 'ch_ticket_new' THEN COALESCE(mavi.ch_ticket_new, 'both'::public.notification_channel)
          WHEN 'ch_ticket_assigned' THEN COALESCE(mavi.ch_ticket_assigned, 'both'::public.notification_channel)
          WHEN 'ch_ticket_status' THEN COALESCE(mavi.ch_ticket_status, 'both'::public.notification_channel)
          WHEN 'ch_ticket_critical' THEN COALESCE(mavi.ch_ticket_critical, 'both'::public.notification_channel)
          WHEN 'ch_hms_risk_assigned' THEN COALESCE(mavi.ch_hms_risk_assigned, 'both'::public.notification_channel)
          WHEN 'ch_hms_sja_assigned' THEN COALESCE(mavi.ch_hms_sja_assigned, 'both'::public.notification_channel)
          WHEN 'ch_hms_ros_avvik_signal' THEN COALESCE(mavi.ch_hms_ros_avvik_signal, 'both'::public.notification_channel)
          WHEN 'ch_hms_sja_expired' THEN COALESCE(mavi.ch_hms_sja_expired, 'both'::public.notification_channel)
          WHEN 'ch_hms' THEN COALESCE(mavi.ch_hms, 'both'::public.notification_channel)
          WHEN 'ch_equipment' THEN COALESCE(mavi.ch_equipment, 'both'::public.notification_channel)
          WHEN 'ch_user_approval' THEN COALESCE(mavi.ch_user_approval, 'both'::public.notification_channel)
          WHEN 'ch_partner_route_ack_internal' THEN COALESCE(mavi.ch_partner_route_ack_internal, 'both'::public.notification_channel)
          WHEN 'ch_partner_route_pending_internal' THEN COALESCE(mavi.ch_partner_route_pending_internal, 'both'::public.notification_channel)
          WHEN 'ch_sap_route_received' THEN COALESCE(mavi.ch_sap_route_received, 'both'::public.notification_channel)
          WHEN 'ch_partner_rental_internal' THEN COALESCE(mavi.ch_partner_rental_internal, 'both'::public.notification_channel)
          WHEN 'ch_partner_document_internal' THEN COALESCE(mavi.ch_partner_document_internal, 'none'::public.notification_channel)
          WHEN 'ch_partner_deactivated_internal' THEN COALESCE(mavi.ch_partner_deactivated_internal, 'sms'::public.notification_channel)
          ELSE COALESCE(mavi.ch_general, 'both'::public.notification_channel)
        END
      ELSE
        CASE d.column_name
          WHEN 'ch_partner_route' THEN COALESCE(partner.ch_partner_route, 'both'::public.notification_channel)
          WHEN 'ch_partner_route_owner' THEN COALESCE(partner.ch_partner_route_owner, 'both'::public.notification_channel)
          WHEN 'ch_partner_route_reminder' THEN COALESCE(partner.ch_partner_route_reminder, 'both'::public.notification_channel)
          WHEN 'ch_partner_route_rejected' THEN COALESCE(partner.ch_partner_route_rejected, 'both'::public.notification_channel)
          WHEN 'ch_partner_route_accepted' THEN COALESCE(partner.ch_partner_route_accepted, 'sms'::public.notification_channel)
          WHEN 'ch_partner_mass_route' THEN COALESCE(partner.ch_partner_mass_route, 'both'::public.notification_channel)
          WHEN 'ch_partner_document' THEN COALESCE(partner.ch_partner_document, 'both'::public.notification_channel)
          WHEN 'ch_partner_document_folder' THEN COALESCE(partner.ch_partner_document_folder, 'both'::public.notification_channel)
          WHEN 'ch_partner_shared_routine' THEN COALESCE(partner.ch_partner_shared_routine, 'email'::public.notification_channel)
          WHEN 'ch_partner_portal' THEN COALESCE(partner.ch_partner_portal, 'both'::public.notification_channel)
          WHEN 'ch_partner_weekly_summary' THEN COALESCE(partner.ch_partner_weekly_summary, 'both'::public.notification_channel)
          WHEN 'ch_partner_meeting' THEN COALESCE(partner.ch_partner_meeting, 'both'::public.notification_channel)
          WHEN 'ch_partner_compose' THEN COALESCE(partner.ch_partner_compose, 'both'::public.notification_channel)
          WHEN 'ch_vehicle_rental' THEN COALESCE(partner.ch_vehicle_rental, 'both'::public.notification_channel)
          WHEN 'ch_vehicle_rental_status' THEN COALESCE(partner.ch_vehicle_rental_status, 'both'::public.notification_channel)
          WHEN 'ch_partner_vehicle_inactive' THEN COALESCE(partner.ch_partner_vehicle_inactive, 'sms'::public.notification_channel)
          ELSE COALESCE(partner.ch_partner_general, 'both'::public.notification_channel)
        END
    END AS channel
  FROM public.notification_event_definitions d
  WHERE d.is_active = true
  ORDER BY d.scope, d.category_group, d.sort_order, d.title;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_notification_event_channel(
  p_company_id uuid,
  p_event_id text,
  p_channel public.notification_channel
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
    RAISE EXCEPTION 'Kun admin/leder kan endre varselinnstillinger';
  END IF;

  SELECT * INTO d
  FROM public.notification_event_definitions
  WHERE id = p_event_id AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ukjent varseltype: %', p_event_id;
  END IF;

  IF d.scope = 'mavi' THEN
    INSERT INTO public.company_sms_settings (company_id)
    VALUES (p_company_id)
    ON CONFLICT (company_id) DO NOTHING;

    EXECUTE format(
      'UPDATE public.company_sms_settings SET %I = $1, updated_at = now(), updated_by = auth.uid() WHERE company_id = $2',
      d.column_name
    ) USING p_channel, p_company_id;

    IF d.legacy_sms_column IS NOT NULL THEN
      EXECUTE format(
        'UPDATE public.company_sms_settings SET %I = $1 WHERE company_id = $2',
        d.legacy_sms_column
      ) USING p_channel <> 'none'::public.notification_channel, p_company_id;
    END IF;
  ELSE
    INSERT INTO public.company_partner_notification_settings (company_id)
    VALUES (p_company_id)
    ON CONFLICT (company_id) DO NOTHING;

    EXECUTE format(
      'UPDATE public.company_partner_notification_settings SET %I = $1, updated_at = now(), updated_by = auth.uid() WHERE company_id = $2',
      d.column_name
    ) USING p_channel, p_company_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_partner_route_ack_reminder_minutes(
  p_company_id uuid,
  p_minutes int
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_company_id <> public.get_user_company_id() THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;
  IF p_minutes < 15 OR p_minutes > 10080 THEN
    RAISE EXCEPTION 'Minutter må være mellom 15 og 10080';
  END IF;

  INSERT INTO public.company_partner_notification_settings (company_id)
  VALUES (p_company_id)
  ON CONFLICT (company_id) DO NOTHING;

  UPDATE public.company_partner_notification_settings
  SET
    route_ack_reminder_minutes = p_minutes,
    route_ack_reminder_hours = GREATEST(1, (p_minutes + 59) / 60),
    updated_at = now(),
    updated_by = auth.uid()
  WHERE company_id = p_company_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_company_notification_events TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_notification_event_channel TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_partner_route_ack_reminder_minutes TO authenticated;
