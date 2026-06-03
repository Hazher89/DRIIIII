-- Avansert varsel: SMS + e-post per hendelse (sms | email | both | none) + logg + audit.

-- ── Kanaler ─────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_channel') THEN
    CREATE TYPE public.notification_channel AS ENUM ('sms', 'email', 'both', 'none');
  END IF;
END $$;

-- ── Firma: MAVI-ansatte (utvider company_sms_settings) ───────────────────────
ALTER TABLE public.company_sms_settings
  ADD COLUMN IF NOT EXISTS ch_absence_request public.notification_channel,
  ADD COLUMN IF NOT EXISTS ch_absence_decision public.notification_channel,
  ADD COLUMN IF NOT EXISTS ch_ticket_new public.notification_channel,
  ADD COLUMN IF NOT EXISTS ch_ticket_status public.notification_channel,
  ADD COLUMN IF NOT EXISTS ch_ticket_critical public.notification_channel,
  ADD COLUMN IF NOT EXISTS ch_equipment public.notification_channel,
  ADD COLUMN IF NOT EXISTS ch_user_approval public.notification_channel,
  ADD COLUMN IF NOT EXISTS ch_general public.notification_channel;

UPDATE public.company_sms_settings SET
  ch_absence_request = CASE WHEN sms_absence_request THEN 'both'::public.notification_channel ELSE 'none'::public.notification_channel END,
  ch_absence_decision = CASE WHEN sms_absence_decision THEN 'both'::public.notification_channel ELSE 'none'::public.notification_channel END,
  ch_ticket_new = CASE WHEN sms_ticket_new THEN 'both'::public.notification_channel ELSE 'none'::public.notification_channel END,
  ch_ticket_status = CASE WHEN sms_ticket_status THEN 'both'::public.notification_channel ELSE 'none'::public.notification_channel END,
  ch_ticket_critical = CASE WHEN sms_ticket_critical THEN 'both'::public.notification_channel ELSE 'none'::public.notification_channel END,
  ch_equipment = CASE WHEN sms_equipment THEN 'both'::public.notification_channel ELSE 'none'::public.notification_channel END,
  ch_user_approval = CASE WHEN COALESCE(sms_user_approval, true) THEN 'both'::public.notification_channel ELSE 'none'::public.notification_channel END,
  ch_general = CASE WHEN sms_general THEN 'both'::public.notification_channel ELSE 'none'::public.notification_channel END
WHERE ch_absence_request IS NULL;

ALTER TABLE public.company_sms_settings
  ALTER COLUMN ch_absence_request SET DEFAULT 'both',
  ALTER COLUMN ch_absence_decision SET DEFAULT 'both',
  ALTER COLUMN ch_ticket_new SET DEFAULT 'both',
  ALTER COLUMN ch_ticket_status SET DEFAULT 'both',
  ALTER COLUMN ch_ticket_critical SET DEFAULT 'both',
  ALTER COLUMN ch_equipment SET DEFAULT 'both',
  ALTER COLUMN ch_user_approval SET DEFAULT 'both',
  ALTER COLUMN ch_general SET DEFAULT 'both';

-- ── Firma: samarbeidspartnere ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.company_partner_notification_settings (
  company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  ch_partner_route public.notification_channel NOT NULL DEFAULT 'both',
  ch_partner_route_owner public.notification_channel NOT NULL DEFAULT 'both',
  ch_partner_meeting public.notification_channel NOT NULL DEFAULT 'both',
  ch_partner_portal public.notification_channel NOT NULL DEFAULT 'both',
  ch_partner_compose public.notification_channel NOT NULL DEFAULT 'both',
  ch_vehicle_rental public.notification_channel NOT NULL DEFAULT 'both',
  ch_vehicle_rental_status public.notification_channel NOT NULL DEFAULT 'both',
  ch_partner_general public.notification_channel NOT NULL DEFAULT 'both',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

ALTER TABLE public.company_partner_notification_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS company_partner_notification_settings_co ON public.company_partner_notification_settings;
CREATE POLICY company_partner_notification_settings_co ON public.company_partner_notification_settings
  FOR ALL
  USING (company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid()))
  WITH CHECK (company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid()));

-- ── Brukerpreferanser ───────────────────────────────────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS email_opt_in BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS notify_channel_preference public.notification_channel NOT NULL DEFAULT 'both';

-- ── E-post outbox metadata ──────────────────────────────────────────────────
ALTER TABLE public.email_outbox
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS to_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS triggered_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

-- ── Audit (sendt / hoppet over) ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.notification_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
  partner_id UUID REFERENCES public.partners(id) ON DELETE SET NULL,
  event_channel TEXT NOT NULL CHECK (event_channel IN ('sms', 'email')),
  category TEXT,
  setting_key TEXT,
  recipient TEXT,
  user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  status TEXT NOT NULL CHECK (status IN ('queued', 'skipped')),
  skip_reason TEXT,
  description TEXT,
  sms_outbox_id UUID REFERENCES public.sms_outbox(id) ON DELETE SET NULL,
  email_outbox_id UUID REFERENCES public.email_outbox(id) ON DELETE SET NULL,
  reference_type TEXT,
  reference_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notification_audit_company_created
  ON public.notification_audit (company_id, created_at DESC);

ALTER TABLE public.notification_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notification_audit_company ON public.notification_audit;
CREATE POLICY notification_audit_company ON public.notification_audit
  FOR SELECT
  USING (company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid()));

-- ── Hjelpefunksjoner ────────────────────────────────────────────────────────
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
    ELSE ch := s.ch_general;
  END CASE;
  IF ch IS NULL THEN
    CASE p_key
      WHEN 'absence_request' THEN RETURN CASE WHEN s.sms_absence_request THEN 'sms'::public.notification_channel ELSE 'none'::public.notification_channel END;
      WHEN 'absence_decision' THEN RETURN CASE WHEN s.sms_absence_decision THEN 'sms'::public.notification_channel ELSE 'none'::public.notification_channel END;
      WHEN 'ticket_new' THEN RETURN CASE WHEN s.sms_ticket_new THEN 'sms'::public.notification_channel ELSE 'none'::public.notification_channel END;
      WHEN 'ticket_status' THEN RETURN CASE WHEN s.sms_ticket_status THEN 'sms'::public.notification_channel ELSE 'none'::public.notification_channel END;
      WHEN 'ticket_critical' THEN RETURN CASE WHEN s.sms_ticket_critical THEN 'sms'::public.notification_channel ELSE 'none'::public.notification_channel END;
      WHEN 'equipment' THEN RETURN CASE WHEN s.sms_equipment THEN 'sms'::public.notification_channel ELSE 'none'::public.notification_channel END;
      WHEN 'user_approval' THEN RETURN CASE WHEN COALESCE(s.sms_user_approval, true) THEN 'sms'::public.notification_channel ELSE 'none'::public.notification_channel END;
      ELSE RETURN CASE WHEN s.sms_general THEN 'sms'::public.notification_channel ELSE 'none'::public.notification_channel END;
    END CASE;
  END IF;
  RETURN ch;
END;
$$;

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
    ELSE RETURN s.ch_partner_general;
  END CASE;
END;
$$;

CREATE OR REPLACE FUNCTION public.user_effective_notify_channel(p_user_id UUID)
RETURNS public.notification_channel
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT notify_channel_preference FROM public.profiles WHERE id = p_user_id),
    'both'::public.notification_channel
  );
$$;

CREATE OR REPLACE FUNCTION public.user_accepts_email(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT email_opt_in FROM public.profiles WHERE id = p_user_id),
    true
  );
$$;

CREATE OR REPLACE FUNCTION public.company_sms_enabled(p_company_id UUID, p_key TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  ch public.notification_channel;
  u_ch public.notification_channel;
BEGIN
  ch := public.company_employee_notification_channel(p_company_id, p_key);
  RETURN ch IN ('sms'::public.notification_channel, 'both'::public.notification_channel);
END;
$$;

CREATE OR REPLACE FUNCTION public.company_email_enabled(p_company_id UUID, p_key TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  ch public.notification_channel;
BEGIN
  ch := public.company_employee_notification_channel(p_company_id, p_key);
  RETURN ch IN ('email'::public.notification_channel, 'both'::public.notification_channel);
END;
$$;

CREATE OR REPLACE FUNCTION public.company_partner_sms_enabled(p_company_id UUID, p_key TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.company_partner_notification_channel(p_company_id, p_key)
    IN ('sms'::public.notification_channel, 'both'::public.notification_channel);
$$;

CREATE OR REPLACE FUNCTION public.company_partner_email_enabled(p_company_id UUID, p_key TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.company_partner_notification_channel(p_company_id, p_key)
    IN ('email'::public.notification_channel, 'both'::public.notification_channel);
$$;

CREATE OR REPLACE FUNCTION public.log_notification_audit(
  p_company_id UUID,
  p_event_channel TEXT,
  p_category TEXT,
  p_setting_key TEXT,
  p_recipient TEXT,
  p_user_id UUID,
  p_status TEXT,
  p_skip_reason TEXT,
  p_description TEXT,
  p_sms_outbox_id UUID DEFAULT NULL,
  p_email_outbox_id UUID DEFAULT NULL,
  p_partner_id UUID DEFAULT NULL,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.notification_audit (
    company_id, partner_id, event_channel, category, setting_key,
    recipient, user_id, status, skip_reason, description,
    sms_outbox_id, email_outbox_id, reference_type, reference_id
  ) VALUES (
    p_company_id, p_partner_id, p_event_channel, p_category, p_setting_key,
    p_recipient, p_user_id, p_status, p_skip_reason, p_description,
    p_sms_outbox_id, p_email_outbox_id, p_reference_type, p_reference_id
  );
END;
$$;

-- ── queue_email utvidet ───────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.queue_email(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, UUID);

CREATE OR REPLACE FUNCTION public.queue_email(
  p_company_id UUID,
  p_to_email TEXT,
  p_subject TEXT,
  p_body TEXT,
  p_category TEXT DEFAULT NULL,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id UUID DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_to_user_id UUID DEFAULT NULL,
  p_triggered_by_user_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_id UUID;
  v_email TEXT;
BEGIN
  v_email := trim(lower(coalesce(p_to_email, '')));
  IF v_email = '' OR position('@' IN v_email) < 2 THEN
    RETURN NULL;
  END IF;
  IF p_subject IS NULL OR length(trim(p_subject)) = 0 THEN
    RETURN NULL;
  END IF;
  IF p_body IS NULL OR length(trim(p_body)) = 0 THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.email_outbox (
    company_id, to_email, subject, body, category, reference_type, reference_id,
    description, to_user_id, triggered_by_user_id
  ) VALUES (
    p_company_id,
    v_email,
    left(trim(p_subject), 500),
    left(trim(p_body), 50000),
    p_category,
    p_reference_type,
    p_reference_id,
    p_description,
    p_to_user_id,
    COALESCE(p_triggered_by_user_id, auth.uid())
  )
  RETURNING id INTO new_id;

  RETURN new_id;
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
  v_ch public.notification_channel;
  v_user_ch public.notification_channel;
  v_email TEXT;
  v_id UUID;
  v_enabled BOOLEAN;
BEGIN
  IF p_partner_scope THEN
    v_enabled := public.company_partner_email_enabled(p_company_id, p_setting_key);
  ELSE
    v_enabled := public.company_email_enabled(p_company_id, p_setting_key);
  END IF;

  IF NOT v_enabled THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'email', p_category, p_setting_key,
      coalesce(p_to_email, ''), p_user_id, 'skipped', 'company_channel_off',
      coalesce(p_description, p_subject), NULL, NULL, NULL, p_reference_type, p_reference_id
    );
    RETURN NULL;
  END IF;

  IF p_user_id IS NOT NULL THEN
    IF NOT public.user_accepts_email(p_user_id) THEN
      PERFORM public.log_notification_audit(
        p_company_id, 'email', p_category, p_setting_key,
        coalesce(p_to_email, ''), p_user_id, 'skipped', 'user_email_opt_out',
        coalesce(p_description, p_subject), NULL, NULL, NULL, p_reference_type, p_reference_id
      );
      RETURN NULL;
    END IF;
    v_user_ch := public.user_effective_notify_channel(p_user_id);
    IF v_user_ch = 'none'::public.notification_channel OR v_user_ch = 'sms'::public.notification_channel THEN
      PERFORM public.log_notification_audit(
        p_company_id, 'email', p_category, p_setting_key,
        coalesce(p_to_email, ''), p_user_id, 'skipped', 'user_pref_no_email',
        coalesce(p_description, p_subject), NULL, NULL, NULL, p_reference_type, p_reference_id
      );
      RETURN NULL;
    END IF;
    v_email := coalesce(
      (SELECT trim(lower(email)) FROM public.profiles WHERE id = p_user_id),
      trim(lower(p_to_email))
    );
  ELSE
    v_email := trim(lower(p_to_email));
  END IF;

  IF v_email IS NULL OR v_email = '' THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'email', p_category, p_setting_key,
      '', p_user_id, 'skipped', 'missing_email',
      coalesce(p_description, p_subject), NULL, NULL, NULL, p_reference_type, p_reference_id
    );
    RETURN NULL;
  END IF;

  v_id := public.queue_email(
    p_company_id, v_email, p_subject, p_body,
    p_category, p_reference_type, p_reference_id,
    p_description, p_user_id, auth.uid()
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

DROP FUNCTION IF EXISTS public.queue_sms_if_allowed(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, UUID, TEXT
);
DROP FUNCTION IF EXISTS public.queue_sms_if_allowed(
  UUID, UUID, TEXT, TEXT, TEXT, TEXT, UUID
);

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
  v_user_ch public.notification_channel;
  v_id UUID;
  v_enabled BOOLEAN;
  v_phone TEXT;
BEGIN
  IF p_partner_scope THEN
    v_enabled := public.company_partner_sms_enabled(p_company_id, p_setting_key);
  ELSE
    v_enabled := public.company_sms_enabled(p_company_id, p_setting_key);
  END IF;

  IF NOT v_enabled THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'sms', p_category, p_setting_key,
      coalesce(p_phone, ''), p_user_id, 'skipped', 'company_channel_off',
      coalesce(p_description, left(p_message, 120)), NULL, NULL, NULL, p_reference_type, p_reference_id
    );
    RETURN NULL;
  END IF;

  IF p_user_id IS NOT NULL AND NOT public.user_accepts_sms(p_user_id) THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'sms', p_category, p_setting_key,
      coalesce(p_phone, ''), p_user_id, 'skipped', 'user_sms_opt_out',
      coalesce(p_description, left(p_message, 120)), NULL, NULL, NULL, p_reference_type, p_reference_id
    );
    RETURN NULL;
  END IF;

  IF p_user_id IS NOT NULL THEN
    v_user_ch := public.user_effective_notify_channel(p_user_id);
    IF v_user_ch = 'none'::public.notification_channel OR v_user_ch = 'email'::public.notification_channel THEN
      PERFORM public.log_notification_audit(
        p_company_id, 'sms', p_category, p_setting_key,
        coalesce(p_phone, ''), p_user_id, 'skipped', 'user_pref_no_sms',
        coalesce(p_description, left(p_message, 120)), NULL, NULL, NULL, p_reference_type, p_reference_id
      );
      RETURN NULL;
    END IF;
  END IF;

  v_id := public.queue_sms(
    p_company_id,
    COALESCE(
      (SELECT phone_normalized FROM public.profiles WHERE id = p_user_id),
      p_phone
    ),
    p_message,
    p_category,
    p_reference_type,
    p_reference_id,
    p_user_id,
    auth.uid()
  );

  IF v_id IS NOT NULL THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'sms', p_category, p_setting_key,
      coalesce(p_phone, ''), p_user_id, 'queued', NULL,
      coalesce(p_description, left(p_message, 120)), v_id, NULL, NULL, p_reference_type, p_reference_id
    );
  END IF;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.queue_email_if_allowed TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.queue_sms_if_allowed TO authenticated, service_role;

-- Partner-scope SMS (rute, møte, …)
CREATE OR REPLACE FUNCTION public.queue_partner_sms_if_allowed(
  p_company_id UUID,
  p_phone TEXT,
  p_message TEXT,
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
  SELECT public.queue_sms_if_allowed(
    p_company_id, NULL, p_phone, p_message, p_category,
    p_reference_type, p_reference_id, p_setting_key, p_description, true
  );
$$;

-- ── E-post logg: ansatte (superadmin) ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.list_company_email_log(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0,
  p_search TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_from_date TIMESTAMPTZ DEFAULT NULL,
  p_to_date TIMESTAMPTZ DEFAULT NULL,
  p_recipient TEXT DEFAULT NULL,
  p_sender TEXT DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  created_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  to_email TEXT,
  subject TEXT,
  body TEXT,
  description TEXT,
  category TEXT,
  reference_type TEXT,
  reference_id UUID,
  error_message TEXT,
  attempts INT,
  recipient_name TEXT,
  recipient_user_id UUID,
  triggered_by_name TEXT,
  triggered_by_user_id UUID,
  delivery_status TEXT,
  sender_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_role TEXT;
BEGIN
  SELECT company_id, role::text INTO v_company_id, v_role
  FROM public.profiles WHERE id = auth.uid();

  IF v_role IS DISTINCT FROM 'superadmin' THEN
    RAISE EXCEPTION 'Kun superadmin har tilgang til e-post-logg';
  END IF;

  RETURN QUERY
  SELECT
    o.id,
    o.created_at,
    o.sent_at,
    o.to_email,
    o.subject,
    o.body,
    o.description,
    o.category,
    o.reference_type,
    o.reference_id,
    o.error_message,
    o.attempts,
    COALESCE(pr.full_name, o.to_email) AS recipient_name,
    o.to_user_id AS recipient_user_id,
    COALESCE(pt.full_name, 'System (automatisk)') AS triggered_by_name,
    o.triggered_by_user_id,
    CASE
      WHEN o.sent_at IS NOT NULL THEN 'sendt'
      WHEN o.error_message IS NOT NULL AND o.attempts >= 3 THEN 'feilet'
      WHEN o.error_message IS NOT NULL THEN 'feil'
      ELSE 'i_ko'
    END AS delivery_status,
    'ikkesvar@driftpro.no'::text AS sender_name
  FROM public.email_outbox o
  LEFT JOIN public.profiles pr ON pr.id = o.to_user_id
  LEFT JOIN public.profiles pt ON pt.id = o.triggered_by_user_id
  WHERE o.company_id = v_company_id
    AND (p_category IS NULL OR o.category = p_category)
    AND (p_from_date IS NULL OR o.created_at >= p_from_date)
    AND (p_to_date IS NULL OR o.created_at <= p_to_date)
    AND (
      p_status IS NULL
      OR (p_status = 'sendt' AND o.sent_at IS NOT NULL)
      OR (p_status = 'i_ko' AND o.sent_at IS NULL AND (o.error_message IS NULL OR o.attempts < 3))
      OR (p_status = 'feilet' AND o.sent_at IS NULL AND o.attempts >= 3)
    )
    AND (
      p_recipient IS NULL OR length(trim(p_recipient)) = 0
      OR o.to_email ILIKE '%' || trim(p_recipient) || '%'
      OR pr.full_name ILIKE '%' || trim(p_recipient) || '%'
    )
    AND (
      p_sender IS NULL OR length(trim(p_sender)) = 0
      OR pt.full_name ILIKE '%' || trim(p_sender) || '%'
    )
    AND (
      p_search IS NULL OR length(trim(p_search)) = 0
      OR o.subject ILIKE '%' || trim(p_search) || '%'
      OR o.body ILIKE '%' || trim(p_search) || '%'
      OR o.description ILIKE '%' || trim(p_search) || '%'
      OR o.to_email ILIKE '%' || trim(p_search) || '%'
    )
  ORDER BY o.created_at DESC
  LIMIT greatest(p_limit, 1)
  OFFSET greatest(p_offset, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.count_company_email_log(
  p_search TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_from_date TIMESTAMPTZ DEFAULT NULL,
  p_to_date TIMESTAMPTZ DEFAULT NULL,
  p_recipient TEXT DEFAULT NULL,
  p_sender TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c BIGINT;
BEGIN
  SELECT count(*)::bigint INTO c
  FROM public.list_company_email_log(1000000, 0, p_search, p_category, p_status, p_from_date, p_to_date, p_recipient, p_sender);
  RETURN c;
END;
$$;

-- ── E-post logg: samarbeid ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_partner_scope_email_category(p_category TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(p_category, '') IN (
    'partner_route', 'partner_route_owner', 'partner_meeting', 'partner_portal',
    'partner_compose', 'vehicle_rental', 'vehicle_rental_status', 'partner_route_share',
    'partner_route_ack', 'absence', 'ticket'
  ) OR COALESCE(p_category, '') LIKE 'partner%';
$$;

CREATE OR REPLACE FUNCTION public.list_partner_email_log(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0,
  p_search TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_from_date TIMESTAMPTZ DEFAULT NULL,
  p_to_date TIMESTAMPTZ DEFAULT NULL,
  p_recipient TEXT DEFAULT NULL,
  p_sender TEXT DEFAULT NULL,
  p_partner_id UUID DEFAULT NULL,
  p_sort TEXT DEFAULT 'created_desc'
)
RETURNS TABLE (
  id UUID,
  created_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  to_email TEXT,
  subject TEXT,
  body TEXT,
  description TEXT,
  category TEXT,
  reference_type TEXT,
  reference_id UUID,
  error_message TEXT,
  attempts INT,
  recipient_name TEXT,
  recipient_user_id UUID,
  triggered_by_name TEXT,
  triggered_by_user_id UUID,
  delivery_status TEXT,
  sender_name TEXT,
  partner_name TEXT,
  context_label TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_company_id UUID;
BEGIN
  IF NOT public.user_can_view_partner_sms_log() THEN
    RAISE EXCEPTION 'Ingen tilgang til partner e-post-logg';
  END IF;

  SELECT company_id INTO v_company_id FROM public.profiles WHERE id = auth.uid();

  RETURN QUERY
  SELECT
    o.id,
    o.created_at,
    o.sent_at,
    o.to_email,
    o.subject,
    o.body,
    o.description,
    o.category,
    o.reference_type,
    o.reference_id,
    o.error_message,
    o.attempts,
    o.to_email AS recipient_name,
    o.to_user_id AS recipient_user_id,
    COALESCE(pt.full_name, 'System') AS triggered_by_name,
    o.triggered_by_user_id,
    CASE
      WHEN o.sent_at IS NOT NULL THEN 'sendt'
      WHEN o.error_message IS NOT NULL AND o.attempts >= 3 THEN 'feilet'
      WHEN o.error_message IS NOT NULL THEN 'feil'
      ELSE 'i_ko'
    END AS delivery_status,
    'ikkesvar@driftpro.no'::text AS sender_name,
    COALESCE(p_route.name, p_ref.name) AS partner_name,
    CASE
      WHEN o.category = 'partner_route_share' THEN 'Rute sendt (e-post)'
      WHEN o.category = 'partner_route_ack' THEN 'Rute kvittering'
      ELSE COALESCE(o.description, o.category, 'E-post')
    END AS context_label
  FROM public.email_outbox o
  LEFT JOIN public.profiles pt ON pt.id = o.triggered_by_user_id
  LEFT JOIN public.partner_route_shares prs
    ON o.reference_type = 'partner_route_shares' AND o.reference_id = prs.id
  LEFT JOIN public.partners p_route ON p_route.id = prs.partner_id
  LEFT JOIN public.partners p_ref ON p_ref.id = prs.partner_id
  WHERE o.company_id = v_company_id
    AND public.is_partner_scope_email_category(o.category)
    AND (p_partner_id IS NULL OR prs.partner_id = p_partner_id OR p_ref.id = p_partner_id)
    AND (p_category IS NULL OR o.category = p_category)
    AND (p_from_date IS NULL OR o.created_at >= p_from_date)
    AND (p_to_date IS NULL OR o.created_at <= p_to_date)
    AND (
      p_status IS NULL
      OR (p_status = 'sendt' AND o.sent_at IS NOT NULL)
      OR (p_status = 'i_ko' AND o.sent_at IS NULL AND (o.error_message IS NULL OR o.attempts < 3))
      OR (p_status = 'feilet' AND o.sent_at IS NULL AND o.attempts >= 3)
    )
    AND (
      p_recipient IS NULL OR length(trim(p_recipient)) = 0
      OR o.to_email ILIKE '%' || trim(p_recipient) || '%'
    )
    AND (
      p_search IS NULL OR length(trim(p_search)) = 0
      OR o.subject ILIKE '%' || trim(p_search) || '%'
      OR o.body ILIKE '%' || trim(p_search) || '%'
      OR o.description ILIKE '%' || trim(p_search) || '%'
    )
  ORDER BY
    CASE WHEN p_sort = 'created_asc' THEN o.created_at END ASC,
    CASE WHEN p_sort = 'sent_desc' THEN o.sent_at END DESC NULLS LAST,
    o.created_at DESC
  LIMIT greatest(p_limit, 1)
  OFFSET greatest(p_offset, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.count_partner_email_log(
  p_search TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_from_date TIMESTAMPTZ DEFAULT NULL,
  p_to_date TIMESTAMPTZ DEFAULT NULL,
  p_recipient TEXT DEFAULT NULL,
  p_partner_id UUID DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c BIGINT;
BEGIN
  IF NOT public.user_can_view_partner_sms_log() THEN
    RETURN 0;
  END IF;
  SELECT count(*)::bigint INTO c
  FROM public.list_partner_email_log(
    1000000, 0, p_search, p_category, p_status, p_from_date, p_to_date, p_recipient, NULL, p_partner_id
  );
  RETURN c;
END;
$$;

-- ── Audit-logg ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.list_notification_audit(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0,
  p_channel TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_partner_scope BOOLEAN DEFAULT NULL,
  p_from_date TIMESTAMPTZ DEFAULT NULL,
  p_to_date TIMESTAMPTZ DEFAULT NULL,
  p_search TEXT DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  created_at TIMESTAMPTZ,
  event_channel TEXT,
  category TEXT,
  setting_key TEXT,
  recipient TEXT,
  status TEXT,
  skip_reason TEXT,
  description TEXT,
  partner_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_role TEXT;
BEGIN
  SELECT company_id, role::text INTO v_company_id, v_role
  FROM public.profiles WHERE id = auth.uid();

  IF v_role IS DISTINCT FROM 'superadmin'
     AND NOT public.user_can_view_partner_sms_log() THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  RETURN QUERY
  SELECT
    a.id,
    a.created_at,
    a.event_channel,
    a.category,
    a.setting_key,
    a.recipient,
    a.status,
    a.skip_reason,
    a.description,
    p.name AS partner_name
  FROM public.notification_audit a
  LEFT JOIN public.partners p ON p.id = a.partner_id
  WHERE a.company_id = v_company_id
    AND (p_channel IS NULL OR a.event_channel = p_channel)
    AND (p_status IS NULL OR a.status = p_status)
    AND (p_category IS NULL OR a.category = p_category)
    AND (p_from_date IS NULL OR a.created_at >= p_from_date)
    AND (p_to_date IS NULL OR a.created_at <= p_to_date)
    AND (
      p_partner_scope IS NULL
      OR (p_partner_scope = true AND a.partner_id IS NOT NULL)
      OR (p_partner_scope = false AND a.partner_id IS NULL
          AND COALESCE(a.setting_key, '') NOT LIKE 'partner%'
          AND COALESCE(a.setting_key, '') NOT LIKE 'vehicle_rental%')
    )
    AND (
      p_search IS NULL OR length(trim(p_search)) = 0
      OR a.description ILIKE '%' || trim(p_search) || '%'
      OR a.recipient ILIKE '%' || trim(p_search) || '%'
      OR a.skip_reason ILIKE '%' || trim(p_search) || '%'
    )
  ORDER BY a.created_at DESC
  LIMIT greatest(p_limit, 1)
  OFFSET greatest(p_offset, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_company_email_log TO authenticated;
GRANT EXECUTE ON FUNCTION public.count_company_email_log TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_partner_email_log TO authenticated;
GRANT EXECUTE ON FUNCTION public.count_partner_email_log TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_notification_audit TO authenticated;

-- Oppdater ticket-trigger til queue_email_if_allowed
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
      AND role IN ('leder', 'admin', 'superadmin')
      AND is_active = true
      AND coalesce(email, '') <> ''
  LOOP
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
      AND role IN ('leder', 'admin', 'superadmin')
      AND is_active = true
      AND coalesce(email, '') <> ''
  LOOP
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
