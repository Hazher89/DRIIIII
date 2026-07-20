-- Push-varsler til sjåfører (og andre innloggede med FCM-token) ved rute-utsendelse.

CREATE TABLE IF NOT EXISTS public.user_push_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  fcm_token TEXT NOT NULL,
  platform TEXT,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_active BOOLEAN NOT NULL DEFAULT true,
  UNIQUE (profile_id, fcm_token)
);

CREATE INDEX IF NOT EXISTS idx_user_push_devices_active_profile
  ON public.user_push_devices (profile_id)
  WHERE is_active = true;

CREATE TABLE IF NOT EXISTS public.push_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
  profile_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  fcm_token TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB NOT NULL DEFAULT '{}'::jsonb,
  category TEXT,
  reference_type TEXT,
  reference_id UUID,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at TIMESTAMPTZ,
  error_message TEXT,
  attempts INT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_push_outbox_unsent
  ON public.push_outbox (created_at)
  WHERE sent_at IS NULL AND attempts < 5;

ALTER TABLE public.user_push_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.push_outbox ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_push_devices_own ON public.user_push_devices;
CREATE POLICY user_push_devices_own ON public.user_push_devices
  FOR ALL
  USING (profile_id = auth.uid())
  WITH CHECK (profile_id = auth.uid());

DROP POLICY IF EXISTS push_outbox_service_only ON public.push_outbox;
CREATE POLICY push_outbox_service_only ON public.push_outbox
  FOR ALL USING (false) WITH CHECK (false);

CREATE OR REPLACE FUNCTION public.upsert_push_device(
  p_fcm_token TEXT,
  p_platform TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  tok TEXT := trim(coalesce(p_fcm_token, ''));
BEGIN
  IF uid IS NULL OR tok = '' THEN
    RETURN;
  END IF;

  INSERT INTO public.user_push_devices (profile_id, fcm_token, platform, last_seen_at, is_active)
  VALUES (uid, tok, nullif(trim(coalesce(p_platform, '')), ''), now(), true)
  ON CONFLICT (profile_id, fcm_token) DO UPDATE SET
    platform = coalesce(excluded.platform, public.user_push_devices.platform),
    last_seen_at = now(),
    is_active = true;

  UPDATE public.profiles
  SET fcm_token = tok
  WHERE id = uid;
END;
$$;

CREATE OR REPLACE FUNCTION public.deactivate_push_devices()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.user_push_devices
  SET is_active = false
  WHERE profile_id = uid;

  UPDATE public.profiles
  SET fcm_token = NULL
  WHERE id = uid;
END;
$$;

CREATE OR REPLACE FUNCTION public.queue_partner_route_push(
  p_company_id UUID,
  p_profile_id UUID,
  p_fcm_token TEXT,
  p_title TEXT,
  p_body TEXT,
  p_route_share_id UUID,
  p_description TEXT DEFAULT 'Ny rute → sjåfør (push)'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_id UUID;
  tok TEXT := trim(coalesce(p_fcm_token, ''));
BEGIN
  IF tok = '' OR p_profile_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.push_outbox o
    WHERE o.reference_type = 'partner_route_shares'
      AND o.reference_id = p_route_share_id
      AND o.fcm_token = tok
      AND o.created_at > now() - interval '10 minutes'
  ) THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.push_outbox (
    company_id,
    profile_id,
    fcm_token,
    title,
    body,
    data,
    category,
    reference_type,
    reference_id,
    description
  )
  VALUES (
    p_company_id,
    p_profile_id,
    tok,
    left(trim(p_title), 120),
    left(trim(p_body), 500),
    jsonb_build_object(
      'type', 'partner_route',
      'route_share_id', p_route_share_id::text
    ),
    'partner_route',
    'partner_route_shares',
    p_route_share_id,
    p_description
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;

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

  SELECT name INTO shift_name FROM public.fleet_shift_definitions WHERE id = r.shift_id;

  driver_title := 'Ny rute i DriftPro';
  driver_body := 'Ny rute på ' || coalesce(r.unit_code, 'bil') ||
    CASE WHEN r.vehicle_reg IS NOT NULL AND trim(r.vehicle_reg) <> '' THEN ' (' || trim(r.vehicle_reg) || ')' ELSE '' END ||
    CASE WHEN shift_name IS NOT NULL THEN ' · ' || shift_name ELSE '' END ||
    '. Åpne appen for PDF og godkjenning.';

  FOR d IN
    SELECT DISTINCT ON (upd.fcm_token)
      ppa.profile_id,
      upd.fcm_token
    FROM public.partner_portal_accounts ppa
    JOIN public.user_push_devices upd
      ON upd.profile_id = ppa.profile_id
     AND upd.is_active = true
    JOIN public.profiles pr ON pr.id = ppa.profile_id AND pr.is_active = true
    WHERE ppa.partner_vehicle_id = r.partner_vehicle_id
      AND ppa.is_active = true
      AND coalesce(ppa.account_kind, 'driver') = 'driver'
      AND ppa.profile_id IS NOT NULL
    ORDER BY upd.fcm_token, upd.last_seen_at DESC
  LOOP
    IF public.queue_partner_route_push(
      r.company_id,
      d.profile_id,
      d.fcm_token,
      driver_title,
      driver_body,
      p_route_share_id
    ) IS NOT NULL THEN
      n := n + 1;
    END IF;
  END LOOP;

  -- Fallback: eldre enkelt-token på profiles.fcm_token
  FOR d IN
    SELECT DISTINCT ppa.profile_id, pr.fcm_token
    FROM public.partner_portal_accounts ppa
    JOIN public.profiles pr ON pr.id = ppa.profile_id
    WHERE ppa.partner_vehicle_id = r.partner_vehicle_id
      AND ppa.is_active = true
      AND coalesce(ppa.account_kind, 'driver') = 'driver'
      AND ppa.profile_id IS NOT NULL
      AND pr.is_active = true
      AND coalesce(trim(pr.fcm_token), '') <> ''
      AND NOT EXISTS (
        SELECT 1 FROM public.user_push_devices upd
        WHERE upd.profile_id = ppa.profile_id
          AND upd.fcm_token = pr.fcm_token
          AND upd.is_active = true
      )
  LOOP
    IF public.queue_partner_route_push(
      r.company_id,
      d.profile_id,
      d.fcm_token,
      driver_title,
      driver_body,
      p_route_share_id
    ) IS NOT NULL THEN
      n := n + 1;
    END IF;
  END LOOP;

  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.trigger_push_outbox_send()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.invoke_outbox_worker('send-push-outbox', ARRAY[NEW.id]);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_outbox_instant_send ON public.push_outbox;
CREATE TRIGGER trg_push_outbox_instant_send
  AFTER INSERT ON public.push_outbox
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_push_outbox_send();

-- Utvid eksisterende rute-varsel med push til alle innloggede sjåfører med token.
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
  owner_only BOOLEAN;
  sent_phones TEXT[] := ARRAY[]::TEXT[];
  v_skip_email BOOLEAN := false;
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

  SELECT EXISTS (
    SELECT 1
    FROM public.email_outbox e
    WHERE e.reference_type = 'partner_route_shares'
      AND e.reference_id = p_route_share_id
      AND e.category = 'partner_route_share'
      AND e.created_at > now() - interval '10 minutes'
  ) INTO v_skip_email;

  owner_only := coalesce(r.routes_owner_only, true);
  SELECT name INTO shift_name FROM public.fleet_shift_definitions WHERE id = r.shift_id;

  driver_msg := 'Ny rute tildelt ' || coalesce(r.unit_code, '') ||
    CASE WHEN r.vehicle_reg IS NOT NULL AND trim(r.vehicle_reg) <> '' THEN ' (' || trim(r.vehicle_reg) || ')' ELSE '' END ||
    CASE WHEN shift_name IS NOT NULL THEN ' · Skift: ' || shift_name ELSE '' END ||
    '. Logg inn i DriftPro for PDF og godkjenning.';

  owner_msg := 'Ny rute på ' || coalesce(r.unit_code, 'bil') ||
    ' — ' || coalesce(r.partner_name, 'din bedrift') ||
    CASE WHEN shift_name IS NOT NULL THEN ' · ' || shift_name ELSE '' END ||
    '. Logg inn i DriftPro for oversikt og godkjenning.';

  SELECT e.subject, e.body_html
  INTO email_sub, email_body
  FROM public.build_partner_route_published_email(
    r.unit_code,
    r.vehicle_reg,
    r.partner_name,
    shift_name,
    r.title,
    r.share_date,
    r.route_start_at
  ) e;

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

  IF NOT v_skip_email THEN
    n := n + public.notify_partner_owner_emails(
      r.company_id, r.partner_id, email_sub, email_body, 'partner_route_share',
      'partner_route_owner', 'partner_route_shares', r.id, 'Ny rute (e-post HTML)'
    );
  END IF;

  n := n + public.notify_partner_route_driver_push(p_route_share_id);

  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_push_device(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.deactivate_push_devices() TO authenticated;
GRANT EXECUTE ON FUNCTION public.notify_partner_route_driver_push(UUID) TO authenticated, service_role;
