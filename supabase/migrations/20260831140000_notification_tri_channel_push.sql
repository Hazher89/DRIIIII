-- Tre uavhengige kanaler per varseltype: SMS, e-post og push i appen.
-- Endringer i appen trer i kraft umiddelbart via company_notification_event_channels.

CREATE TABLE IF NOT EXISTS public.company_notification_event_channels (
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  event_id TEXT NOT NULL REFERENCES public.notification_event_definitions(id) ON DELETE CASCADE,
  sms_enabled BOOLEAN NOT NULL DEFAULT true,
  email_enabled BOOLEAN NOT NULL DEFAULT true,
  push_enabled BOOLEAN NOT NULL DEFAULT true,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  PRIMARY KEY (company_id, event_id)
);

CREATE INDEX IF NOT EXISTS idx_company_notification_event_channels_company
  ON public.company_notification_event_channels (company_id);

ALTER TABLE public.company_notification_event_channels ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS company_notification_event_channels_read ON public.company_notification_event_channels;
CREATE POLICY company_notification_event_channels_read ON public.company_notification_event_channels
  FOR SELECT TO authenticated
  USING (company_id = public.get_user_company_id());

DROP POLICY IF EXISTS company_notification_event_channels_write ON public.company_notification_event_channels;
CREATE POLICY company_notification_event_channels_write ON public.company_notification_event_channels
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

GRANT SELECT, INSERT, UPDATE, DELETE ON public.company_notification_event_channels TO authenticated;

-- Nye varseltyper (push/SMS/e-post per funksjon)
INSERT INTO public.notification_event_definitions (
  id, scope, settings_table, column_name, setting_key, title, subtitle, category_group, sort_order
) VALUES
  ('partner_deduction', 'partner', 'company_partner_notification_settings', 'ch_partner_compose', 'partner_deduction', 'Bot / trekk', 'Til bedriftsansvarlig i appen', 'SMS-hub & bilutleie', 125),
  ('partner_vehicle_inspection', 'partner', 'company_partner_notification_settings', 'ch_partner_general', 'partner_vehicle_inspection', 'Bilkontroll', 'Inspeksjon med avvik/OK', 'SMS-hub & bilutleie', 155),
  ('partner_workforce_punch', 'partner', 'company_partner_notification_settings', 'ch_partner_general', 'partner_workforce_punch', 'Stempling (workforce)', 'Inn/ut til bil-eier', 'SMS-hub & bilutleie', 156),
  ('partner_route_updated', 'partner', 'company_partner_notification_settings', 'ch_partner_route', 'partner_route_updated', 'Rute endret', 'Etter publisering', 'Ruter', 15),
  ('partner_route_deleted', 'partner', 'company_partner_notification_settings', 'ch_partner_route', 'partner_route_deleted', 'Rute slettet', 'Varsel ved sletting', 'Ruter', 16),
  ('safety_round', 'mavi', 'company_sms_settings', 'ch_hms', 'safety_round', 'Vernerunde', 'Ny runde / funn / tildeling', 'HMS — vernerunde', 105)
ON CONFLICT (id) DO UPDATE SET
  title = EXCLUDED.title,
  subtitle = EXCLUDED.subtitle,
  category_group = EXCLUDED.category_group,
  sort_order = EXCLUDED.sort_order,
  setting_key = EXCLUDED.setting_key,
  is_active = true;

CREATE OR REPLACE FUNCTION public._notification_legacy_channel(
  p_company_id UUID,
  p_event_id TEXT
)
RETURNS public.notification_channel
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d public.notification_event_definitions%ROWTYPE;
  mavi public.company_sms_settings%ROWTYPE;
  partner public.company_partner_notification_settings%ROWTYPE;
  ch public.notification_channel;
BEGIN
  SELECT * INTO d FROM public.notification_event_definitions WHERE id = p_event_id AND is_active = true;
  IF NOT FOUND THEN
    RETURN 'both'::public.notification_channel;
  END IF;

  IF d.scope = 'mavi' THEN
    SELECT * INTO mavi FROM public.company_sms_settings WHERE company_id = p_company_id;
    IF NOT FOUND THEN
      RETURN 'both'::public.notification_channel;
    END IF;
    EXECUTE format('SELECT ($1).%I', d.column_name) INTO ch USING mavi;
  ELSE
    SELECT * INTO partner FROM public.company_partner_notification_settings WHERE company_id = p_company_id;
    IF NOT FOUND THEN
      RETURN 'both'::public.notification_channel;
    END IF;
    EXECUTE format('SELECT ($1).%I', d.column_name) INTO ch USING partner;
  END IF;

  RETURN COALESCE(ch, 'both'::public.notification_channel);
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_notification_event_channels(p_company_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d RECORD;
  leg public.notification_channel;
BEGIN
  FOR d IN SELECT id FROM public.notification_event_definitions WHERE is_active = true LOOP
    IF EXISTS (
      SELECT 1 FROM public.company_notification_event_channels
      WHERE company_id = p_company_id AND event_id = d.id
    ) THEN
      CONTINUE;
    END IF;

    leg := public._notification_legacy_channel(p_company_id, d.id);
    INSERT INTO public.company_notification_event_channels (
      company_id, event_id, sms_enabled, email_enabled, push_enabled
    )
    VALUES (
      p_company_id,
      d.id,
      leg IN ('sms'::public.notification_channel, 'both'::public.notification_channel),
      leg IN ('email'::public.notification_channel, 'both'::public.notification_channel),
      true
    )
    ON CONFLICT (company_id, event_id) DO NOTHING;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_notification_tri_channel(
  p_company_id UUID,
  p_event_id TEXT
)
RETURNS TABLE (sms_enabled BOOLEAN, email_enabled BOOLEAN, push_enabled BOOLEAN)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  row public.company_notification_event_channels%ROWTYPE;
  leg public.notification_channel;
BEGIN
  PERFORM public.ensure_notification_event_channels(p_company_id);

  SELECT * INTO row
  FROM public.company_notification_event_channels
  WHERE company_id = p_company_id AND event_id = p_event_id;

  IF FOUND THEN
    sms_enabled := row.sms_enabled;
    email_enabled := row.email_enabled;
    push_enabled := row.push_enabled;
    RETURN NEXT;
    RETURN;
  END IF;

  leg := public._notification_legacy_channel(p_company_id, p_event_id);
  sms_enabled := leg IN ('sms'::public.notification_channel, 'both'::public.notification_channel);
  email_enabled := leg IN ('email'::public.notification_channel, 'both'::public.notification_channel);
  push_enabled := true;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.company_sms_enabled(p_company_id UUID, p_key TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT t.sms_enabled FROM public.get_notification_tri_channel(p_company_id, p_key) t),
    false
  );
$$;

CREATE OR REPLACE FUNCTION public.company_email_enabled(p_company_id UUID, p_key TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT t.email_enabled FROM public.get_notification_tri_channel(p_company_id, p_key) t),
    false
  );
$$;

CREATE OR REPLACE FUNCTION public.company_push_enabled(p_company_id UUID, p_key TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT t.push_enabled FROM public.get_notification_tri_channel(p_company_id, p_key) t),
    false
  );
$$;

CREATE OR REPLACE FUNCTION public.company_partner_sms_enabled(p_company_id UUID, p_key TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.company_sms_enabled(p_company_id, p_key);
$$;

CREATE OR REPLACE FUNCTION public.company_partner_email_enabled(p_company_id UUID, p_key TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.company_email_enabled(p_company_id, p_key);
$$;

CREATE OR REPLACE FUNCTION public.company_partner_push_enabled(p_company_id UUID, p_key TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.company_push_enabled(p_company_id, p_key);
$$;

DROP FUNCTION IF EXISTS public.get_company_notification_events(UUID);

CREATE OR REPLACE FUNCTION public.get_company_notification_events(p_company_id UUID)
RETURNS TABLE (
  id TEXT,
  scope TEXT,
  setting_key TEXT,
  title TEXT,
  subtitle TEXT,
  category_group TEXT,
  sort_order INT,
  channel public.notification_channel,
  sms_enabled BOOLEAN,
  email_enabled BOOLEAN,
  push_enabled BOOLEAN
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

  PERFORM public.ensure_notification_event_channels(p_company_id);

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
      WHEN c.sms_enabled AND c.email_enabled THEN 'both'::public.notification_channel
      WHEN c.sms_enabled THEN 'sms'::public.notification_channel
      WHEN c.email_enabled THEN 'email'::public.notification_channel
      ELSE 'none'::public.notification_channel
    END AS channel,
    c.sms_enabled,
    c.email_enabled,
    c.push_enabled
  FROM public.notification_event_definitions d
  JOIN public.company_notification_event_channels c
    ON c.company_id = p_company_id AND c.event_id = d.id
  WHERE d.is_active = true
  ORDER BY d.scope, d.category_group, d.sort_order, d.title;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_notification_event_channels(
  p_company_id UUID,
  p_event_id TEXT,
  p_sms_enabled BOOLEAN,
  p_email_enabled BOOLEAN,
  p_push_enabled BOOLEAN
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
    RAISE EXCEPTION 'Kun admin/leder kan endre varselinnstillinger';
  END IF;

  SELECT * INTO d
  FROM public.notification_event_definitions
  WHERE id = p_event_id AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ukjent varseltype: %', p_event_id;
  END IF;

  PERFORM public.ensure_notification_event_channels(p_company_id);

  INSERT INTO public.company_notification_event_channels (
    company_id, event_id, sms_enabled, email_enabled, push_enabled, updated_at, updated_by
  )
  VALUES (
    p_company_id, p_event_id, p_sms_enabled, p_email_enabled, p_push_enabled, now(), auth.uid()
  )
  ON CONFLICT (company_id, event_id) DO UPDATE SET
    sms_enabled = EXCLUDED.sms_enabled,
    email_enabled = EXCLUDED.email_enabled,
    push_enabled = EXCLUDED.push_enabled,
    updated_at = now(),
    updated_by = auth.uid();

  ch := CASE
    WHEN p_sms_enabled AND p_email_enabled THEN 'both'::public.notification_channel
    WHEN p_sms_enabled THEN 'sms'::public.notification_channel
    WHEN p_email_enabled THEN 'email'::public.notification_channel
    ELSE 'none'::public.notification_channel
  END;

  IF d.scope = 'mavi' THEN
    INSERT INTO public.company_sms_settings (company_id)
    VALUES (p_company_id)
    ON CONFLICT (company_id) DO NOTHING;

    EXECUTE format(
      'UPDATE public.company_sms_settings SET %I = $1, updated_at = now(), updated_by = auth.uid() WHERE company_id = $2',
      d.column_name
    ) USING ch, p_company_id;

    IF d.legacy_sms_column IS NOT NULL THEN
      EXECUTE format(
        'UPDATE public.company_sms_settings SET %I = $1 WHERE company_id = $2',
        d.legacy_sms_column
      ) USING p_sms_enabled, p_company_id;
    END IF;
  ELSE
    INSERT INTO public.company_partner_notification_settings (company_id)
    VALUES (p_company_id)
    ON CONFLICT (company_id) DO NOTHING;

    EXECUTE format(
      'UPDATE public.company_partner_notification_settings SET %I = $1, updated_at = now(), updated_by = auth.uid() WHERE company_id = $2',
      d.column_name
    ) USING ch, p_company_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_notification_event_channel(
  p_company_id UUID,
  p_event_id TEXT,
  p_channel public.notification_channel
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.set_notification_event_channels(
    p_company_id,
    p_event_id,
    p_channel IN ('sms'::public.notification_channel, 'both'::public.notification_channel),
    p_channel IN ('email'::public.notification_channel, 'both'::public.notification_channel),
    COALESCE(
      (SELECT push_enabled FROM public.company_notification_event_channels
       WHERE company_id = p_company_id AND event_id = p_event_id),
      true
    )
  );
END;
$$;

-- Push-kø med firmavalg (som SMS/e-post)
CREATE OR REPLACE FUNCTION public.queue_push_if_allowed(
  p_company_id UUID,
  p_user_id UUID,
  p_fcm_token TEXT,
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
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enabled BOOLEAN;
  v_id UUID;
  tok TEXT := trim(coalesce(p_fcm_token, ''));
BEGIN
  IF tok = '' OR p_user_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF p_partner_scope THEN
    v_enabled := public.company_partner_push_enabled(p_company_id, p_setting_key);
  ELSE
    v_enabled := public.company_push_enabled(p_company_id, p_setting_key);
  END IF;

  IF NOT v_enabled THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'push', p_category, p_setting_key,
      tok, p_user_id, 'skipped', 'company_channel_off',
      coalesce(p_description, left(p_body, 120)), NULL, NULL, NULL, p_reference_type, p_reference_id
    );
    RETURN NULL;
  END IF;

  INSERT INTO public.push_outbox (
    company_id, profile_id, fcm_token, title, body, data, category,
    reference_type, reference_id, description
  )
  VALUES (
    p_company_id,
    p_user_id,
    tok,
    left(trim(p_title), 120),
    left(trim(p_body), 500),
    COALESCE(p_data, '{}'::jsonb),
    p_category,
    p_reference_type,
    p_reference_id,
    coalesce(p_description, p_setting_key || ' (push)')
  )
  RETURNING id INTO v_id;

  PERFORM public.log_notification_audit(
    p_company_id, 'push', p_category, p_setting_key,
    tok, p_user_id, 'queued', NULL,
    coalesce(p_description, left(p_body, 120)), NULL, NULL, NULL, p_reference_type, p_reference_id
  );

  RETURN v_id;
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
BEGIN
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

  RETURN n;
END;
$$;

-- HMS: ekte FCM når push er på, ellers in-app rad
CREATE OR REPLACE FUNCTION public.hms_push_notification(
  p_user_id UUID,
  p_company_id UUID,
  p_title TEXT,
  p_body TEXT,
  p_data JSONB DEFAULT '{}'::jsonb,
  p_setting_key TEXT DEFAULT 'hms'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n INT;
  cat TEXT := coalesce(p_data->>'category', p_setting_key);
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  n := public.queue_push_to_profile_if_allowed(
    p_company_id,
    p_user_id,
    p_title,
    p_body,
    cat,
    coalesce(p_data->>'reference_type', 'hms'),
    nullif(p_data->>'reference_id', '')::uuid,
    p_setting_key,
    'HMS push',
    false,
    p_data
  );

  IF n > 0 THEN
    RETURN;
  END IF;

  IF public.company_push_enabled(p_company_id, p_setting_key) THEN
    INSERT INTO public.notifications (user_id, company_id, title, body, type, data)
    VALUES (p_user_id, p_company_id, p_title, p_body, 'push', p_data);
  END IF;
END;
$$;

-- Partner push-funksjoner respekterer firmavalg
CREATE OR REPLACE FUNCTION public.notify_partner_route_driver_push(p_route_share_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  shift_name TEXT;
  driver_title TEXT;
  driver_body TEXT;
  d RECORD;
  n INT := 0;
BEGIN
  SELECT
    prs.*,
    pv.unit_code,
    pv.registration_number AS vehicle_reg,
    p.name AS partner_name,
    p.is_active AS partner_is_active
  INTO r
  FROM public.partner_route_shares prs
  LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
  LEFT JOIN public.partners p ON p.id = prs.partner_id
  WHERE prs.id = p_route_share_id;

  IF r IS NULL
     OR coalesce(r.partner_is_active, false) = false
     OR coalesce(r.dispatch_status, 'sent') <> 'sent'
     OR r.partner_vehicle_id IS NULL THEN
    RETURN 0;
  END IF;

  IF NOT public.partner_route_wants_channel(r.notify_channels, 'app')
     OR NOT public.company_partner_push_enabled(r.company_id, 'partner_route') THEN
    RETURN 0;
  END IF;

  SELECT name INTO shift_name FROM public.fleet_shift_definitions WHERE id = r.shift_id;

  driver_title := 'Ny rute i DriftPro';
  driver_body := 'Ny rute på ' || coalesce(r.unit_code, 'bil') ||
    CASE WHEN r.vehicle_reg IS NOT NULL AND trim(r.vehicle_reg) <> '' THEN ' (' || trim(r.vehicle_reg) || ')' ELSE '' END ||
    CASE WHEN shift_name IS NOT NULL THEN ' · ' || shift_name ELSE '' END ||
    '. Åpne appen for PDF og godkjenning.';

  FOR d IN
    SELECT DISTINCT ppa.profile_id
    FROM public.partner_portal_accounts ppa
    JOIN public.profiles pr ON pr.id = ppa.profile_id AND coalesce(pr.is_active, true) = true
    WHERE ppa.partner_vehicle_id = r.partner_vehicle_id
      AND ppa.is_active = true
      AND coalesce(ppa.account_kind, 'driver') = 'driver'
      AND ppa.profile_id IS NOT NULL
  LOOP
    n := n + public.queue_push_to_profile_if_allowed(
      r.company_id,
      d.profile_id,
      driver_title,
      driver_body,
      'partner_route',
      'partner_route_shares',
      p_route_share_id,
      'partner_route',
      'Ny rute → sjåfør (push)',
      true,
      jsonb_build_object('type', 'partner_route', 'route_share_id', p_route_share_id::text)
    );
  END LOOP;

  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_partner_deduction_owner_push(
  p_company_id UUID,
  p_partner_id UUID,
  p_case_id UUID,
  p_title TEXT,
  p_body TEXT
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d RECORD;
  n INT := 0;
BEGIN
  IF NOT public.company_partner_push_enabled(p_company_id, 'partner_deduction') THEN
    RETURN 0;
  END IF;

  FOR d IN
    SELECT DISTINCT ppa.profile_id
    FROM public.partner_portal_accounts ppa
    JOIN public.profiles pr ON pr.id = ppa.profile_id AND coalesce(pr.is_active, true) = true
    WHERE ppa.partner_id = p_partner_id
      AND ppa.is_active = true
      AND ppa.profile_id IS NOT NULL
      AND coalesce(ppa.account_kind, 'owner') IN ('owner', 'admin')
      AND ppa.partner_vehicle_id IS NULL
  LOOP
    n := n + public.queue_push_to_profile_if_allowed(
      p_company_id,
      d.profile_id,
      p_title,
      p_body,
      'partner_deduction',
      'partner_deduction_cases',
      p_case_id,
      'partner_deduction',
      'Bot/trekk → bedriftsansvarlig (push)',
      true,
      jsonb_build_object('type', 'partner_deduction', 'case_id', p_case_id::text)
    );
  END LOOP;

  RETURN n;
END;
$$;

-- Seed alle eksisterende bedrifter
DO $$
DECLARE
  cid UUID;
BEGIN
  FOR cid IN SELECT id FROM public.companies LOOP
    PERFORM public.ensure_notification_event_channels(cid);
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_notification_tri_channel(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_notification_event_channels(UUID, TEXT, BOOLEAN, BOOLEAN, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.company_push_enabled(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.company_partner_push_enabled(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.queue_push_if_allowed TO service_role;
GRANT EXECUTE ON FUNCTION public.queue_push_to_profile_if_allowed TO service_role;

-- Bilkontroll + stempling respekterer push-valg
CREATE OR REPLACE FUNCTION public.notify_partner_vehicle_inspection_owner_push(
  p_company_id UUID,
  p_partner_id UUID,
  p_inspection_id UUID,
  p_title TEXT,
  p_body TEXT
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d RECORD;
  n INT := 0;
BEGIN
  IF NOT public.company_partner_push_enabled(p_company_id, 'partner_vehicle_inspection') THEN
    RETURN 0;
  END IF;

  FOR d IN
    SELECT DISTINCT ppa.profile_id
    FROM public.partner_portal_accounts ppa
    JOIN public.profiles pr ON pr.id = ppa.profile_id AND coalesce(pr.is_active, true) = true
    WHERE ppa.partner_id = p_partner_id
      AND ppa.is_active = true
      AND ppa.profile_id IS NOT NULL
      AND coalesce(ppa.account_kind, 'owner') IN ('owner', 'admin')
      AND ppa.partner_vehicle_id IS NULL
  LOOP
    n := n + public.queue_push_to_profile_if_allowed(
      p_company_id,
      d.profile_id,
      p_title,
      p_body,
      'partner_inspection',
      'partner_vehicle_inspections',
      p_inspection_id,
      'partner_vehicle_inspection',
      'Bilkontroll → bedriftsansvarlig (push)',
      true,
      jsonb_build_object('type', 'partner_inspection', 'inspection_id', p_inspection_id::text)
    );
  END LOOP;

  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_partner_workforce_punch_owners_push(
  p_company_id uuid,
  p_partner_id uuid,
  p_entry_id uuid,
  p_staff_name text,
  p_action text
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d record;
  n int := 0;
  v_title text;
  v_body text;
BEGIN
  IF NOT public.company_partner_push_enabled(p_company_id, 'partner_workforce_punch') THEN
    RETURN 0;
  END IF;

  IF p_action = 'punch_out' THEN
    v_title := 'Stemplet ut';
    v_body := coalesce(nullif(trim(p_staff_name), ''), 'Ansatt') || ' har stemplet ut.';
  ELSE
    v_title := 'Stemplet inn';
    v_body := coalesce(nullif(trim(p_staff_name), ''), 'Ansatt') || ' har stemplet inn.';
  END IF;

  FOR d IN
    SELECT DISTINCT ppa.profile_id
    FROM public.partner_portal_accounts ppa
    JOIN public.profiles pr ON pr.id = ppa.profile_id AND coalesce(pr.is_active, true) = true
    WHERE ppa.partner_id = p_partner_id
      AND ppa.is_active = true
      AND ppa.account_kind = 'owner'
      AND ppa.profile_id IS NOT NULL
  LOOP
    n := n + public.queue_push_to_profile_if_allowed(
      p_company_id,
      d.profile_id,
      v_title,
      v_body,
      'partner_workforce_punch',
      'partner_time_entries',
      p_entry_id,
      'partner_workforce_punch',
      'Stempling → bil-eier (push)',
      true,
      jsonb_build_object('type', 'partner_workforce_punch', 'entry_id', p_entry_id::text)
    );
  END LOOP;

  RETURN n;
END;
$$;
