-- Sjåføravvik: rapportering fra partnerportal, MAVI-oversikt, chat-søk og varsling.

CREATE TABLE IF NOT EXISTS public.partner_driver_deviations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  partner_vehicle_id UUID REFERENCES public.partner_vehicles(id) ON DELETE SET NULL,
  route_share_id UUID REFERENCES public.partner_route_shares(id) ON DELETE SET NULL,
  reported_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT DEFAULT auth.uid(),
  route_date DATE NOT NULL,
  customer_name TEXT,
  freight_unit TEXT,
  customer_ref TEXT,
  order_ref TEXT,
  comment TEXT NOT NULL CHECK (length(trim(comment)) > 0),
  image_urls TEXT[] NOT NULL DEFAULT '{}',
  video_urls TEXT[] NOT NULL DEFAULT '{}',
  search_text TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'in_progress', 'closed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_partner_driver_deviations_company_created
  ON public.partner_driver_deviations (company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_partner_driver_deviations_vehicle_date
  ON public.partner_driver_deviations (partner_vehicle_id, route_date DESC);
CREATE INDEX IF NOT EXISTS idx_partner_driver_deviations_search
  ON public.partner_driver_deviations USING gin (to_tsvector('simple', coalesce(search_text, '')));

CREATE OR REPLACE FUNCTION public.partner_driver_deviations_set_search_text()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.search_text := lower(trim(both FROM concat_ws(
    ' ',
    coalesce(NEW.freight_unit, ''),
    coalesce(NEW.customer_ref, ''),
    coalesce(NEW.order_ref, ''),
    coalesce(NEW.customer_name, ''),
    coalesce(NEW.comment, '')
  )));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_partner_driver_deviations_search_text
  ON public.partner_driver_deviations;
CREATE TRIGGER trg_partner_driver_deviations_search_text
  BEFORE INSERT OR UPDATE OF freight_unit, customer_ref, order_ref, customer_name, comment
  ON public.partner_driver_deviations
  FOR EACH ROW EXECUTE FUNCTION public.partner_driver_deviations_set_search_text();

ALTER TABLE public.partner_driver_deviations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS partner_driver_deviations_driver_insert
  ON public.partner_driver_deviations;
CREATE POLICY partner_driver_deviations_driver_insert
  ON public.partner_driver_deviations
  FOR INSERT TO authenticated
  WITH CHECK (
    reported_by = auth.uid()
    AND partner_vehicle_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.partner_portal_accounts ppa
      WHERE ppa.profile_id = auth.uid()
        AND coalesce(ppa.is_active, true)
        AND coalesce(ppa.account_kind, 'driver') = 'driver'
        AND ppa.company_id = partner_driver_deviations.company_id
        AND ppa.partner_id = partner_driver_deviations.partner_id
        AND ppa.partner_vehicle_id = partner_driver_deviations.partner_vehicle_id
    )
  );

DROP POLICY IF EXISTS partner_driver_deviations_driver_select
  ON public.partner_driver_deviations;
CREATE POLICY partner_driver_deviations_driver_select
  ON public.partner_driver_deviations
  FOR SELECT TO authenticated
  USING (
    reported_by = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.partner_portal_accounts ppa
      WHERE ppa.profile_id = auth.uid()
        AND coalesce(ppa.is_active, true)
        AND ppa.partner_vehicle_id = partner_driver_deviations.partner_vehicle_id
    )
  );

DROP POLICY IF EXISTS partner_driver_deviations_mavi_select
  ON public.partner_driver_deviations;
CREATE POLICY partner_driver_deviations_mavi_select
  ON public.partner_driver_deviations
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.company_id = partner_driver_deviations.company_id
        AND p.partner_id IS NULL
        AND (
          p.role IN ('admin'::public.user_role, 'superadmin'::public.user_role)
          OR coalesce((p.access_settings ->> 'partners')::boolean, false)
          OR coalesce((p.access_settings ->> 'samarbeidspartnere')::boolean, false)
          OR coalesce((p.access_settings ->> 'partners_admin')::boolean, false)
        )
    )
  );

DROP POLICY IF EXISTS partner_driver_deviations_service_all
  ON public.partner_driver_deviations;
CREATE POLICY partner_driver_deviations_service_all
  ON public.partner_driver_deviations
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION public.list_partner_driver_deviations(
  p_company_id UUID,
  p_query TEXT DEFAULT NULL,
  p_limit INT DEFAULT 50
)
RETURNS SETOF public.partner_driver_deviations
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT d.*
  FROM public.partner_driver_deviations d
  WHERE d.company_id = p_company_id
    AND (
      nullif(trim(p_query), '') IS NULL
      OR d.search_text ILIKE '%' || lower(trim(p_query)) || '%'
    )
  ORDER BY d.created_at DESC
  LIMIT least(greatest(coalesce(p_limit, 50), 1), 200);
$$;

CREATE OR REPLACE FUNCTION public.search_partner_driver_deviations(
  p_company_id UUID,
  p_query TEXT
)
RETURNS SETOF public.partner_driver_deviations
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT d.*
  FROM public.partner_driver_deviations d
  WHERE d.company_id = p_company_id
    AND length(trim(coalesce(p_query, ''))) >= 2
    AND d.search_text ILIKE '%' || lower(trim(p_query)) || '%'
  ORDER BY d.created_at DESC
  LIMIT 25;
$$;

GRANT EXECUTE ON FUNCTION public.list_partner_driver_deviations(UUID, TEXT, INT)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.search_partner_driver_deviations(UUID, TEXT)
  TO authenticated, service_role;

CREATE TABLE IF NOT EXISTS public.partner_driver_deviation_alert_settings (
  company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  enabled BOOLEAN NOT NULL DEFAULT true,
  emails TEXT[] NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

ALTER TABLE public.partner_driver_deviation_alert_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS partner_driver_deviation_alert_settings_admin
  ON public.partner_driver_deviation_alert_settings;
CREATE POLICY partner_driver_deviation_alert_settings_admin
  ON public.partner_driver_deviation_alert_settings
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.company_id = partner_driver_deviation_alert_settings.company_id
        AND p.role IN ('admin'::public.user_role, 'superadmin'::public.user_role)
    )
  )
  WITH CHECK (
    updated_by = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.company_id = partner_driver_deviation_alert_settings.company_id
        AND p.role IN ('admin'::public.user_role, 'superadmin'::public.user_role)
    )
  );

DROP POLICY IF EXISTS partner_driver_deviation_alert_settings_service_all
  ON public.partner_driver_deviation_alert_settings;
CREATE POLICY partner_driver_deviation_alert_settings_service_all
  ON public.partner_driver_deviation_alert_settings
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION public.notify_partner_driver_deviation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enabled BOOLEAN := true;
  v_emails TEXT[] := '{}';
  v_email TEXT;
  v_subject TEXT;
  v_body TEXT;
BEGIN
  SELECT s.enabled, s.emails
  INTO v_enabled, v_emails
  FROM public.partner_driver_deviation_alert_settings s
  WHERE s.company_id = NEW.company_id;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;
  IF NOT coalesce(v_enabled, true) THEN
    RETURN NEW;
  END IF;

  v_subject := 'Nytt sjåføravvik'
    || CASE WHEN nullif(trim(NEW.freight_unit), '') IS NOT NULL
      THEN ' – FU ' || trim(NEW.freight_unit) ELSE '' END;
  v_body := concat_ws(E'\n',
    'Et nytt sjåføravvik er registrert.',
    'Dato: ' || to_char(NEW.route_date, 'DD.MM.YYYY'),
    CASE WHEN nullif(trim(NEW.freight_unit), '') IS NOT NULL
      THEN 'FU: ' || trim(NEW.freight_unit) END,
    CASE WHEN nullif(trim(NEW.customer_name), '') IS NOT NULL
      THEN 'Kunde: ' || trim(NEW.customer_name) END,
    CASE WHEN nullif(trim(NEW.order_ref), '') IS NOT NULL
      THEN 'Ordrenummer: ' || trim(NEW.order_ref) END,
    'Kommentar: ' || trim(NEW.comment),
    '',
    'Åpne DriftPro → Partnere → Sjåføravvik.'
  );

  FOREACH v_email IN ARRAY coalesce(v_emails, '{}') LOOP
    IF nullif(trim(v_email), '') IS NOT NULL THEN
      PERFORM public.queue_email(
        NEW.company_id,
        lower(trim(v_email)),
        v_subject,
        v_body,
        'partner_driver_deviation',
        'partner_driver_deviation',
        NEW.id
      );
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_partner_driver_deviation() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_notify_partner_driver_deviation
  ON public.partner_driver_deviations;
CREATE TRIGGER trg_notify_partner_driver_deviation
  AFTER INSERT ON public.partner_driver_deviations
  FOR EACH ROW EXECUTE FUNCTION public.notify_partner_driver_deviation();

COMMENT ON TABLE public.partner_driver_deviations
  IS 'Avvik rapportert av sjåfører i partnerportalen.';
COMMENT ON TABLE public.partner_driver_deviation_alert_settings
  IS 'E-postvarsling ved nye sjåføravvik per bedrift.';
