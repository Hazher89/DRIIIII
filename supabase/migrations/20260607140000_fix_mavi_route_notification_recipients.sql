-- Rute-/samarbeidsvarsler skal ikke broadcastes til alle avdelingsledere.
-- Kun superadmin, ruteplanlegger-avdeling, eller ansatte med samarbeid/rute-tilgang.

CREATE OR REPLACE FUNCTION public.profile_is_mavi_route_ops_recipient(
  p_company_id UUID,
  p_profile_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    LEFT JOIN public.departments d ON d.id = p.department_id
    WHERE p.id = p_profile_id
      AND p.company_id = p_company_id
      AND p.is_active = true
      AND p.is_approved = true
      AND (
        p.role = 'superadmin'::public.user_role
        OR coalesce(p.access_settings->>'samarbeidspartnere', 'false') = 'true'
        OR coalesce(p.access_settings->>'partners', 'false') = 'true'
        OR coalesce(p.access_settings->>'fleet_ruter', 'false') = 'true'
        OR coalesce(p.access_settings->>'partners_admin', 'false') = 'true'
        OR lower(coalesce(d.name, '')) LIKE '%rute%'
      )
  );
$$;

COMMENT ON FUNCTION public.profile_is_mavi_route_ops_recipient(UUID, UUID) IS
  'True når profilen skal motta interne rute/samarbeid-varsler (ikke alle ledere).';

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
    SELECT p.id, p.email, p.phone_normalized, p.phone
    FROM public.profiles p
    LEFT JOIN public.departments d ON d.id = p.department_id
    WHERE p.company_id = p_company_id
      AND p.is_active = true
      AND p.is_approved = true
      AND (
        p.role = 'superadmin'::public.user_role
        OR coalesce(p.access_settings->>'samarbeidspartnere', 'false') = 'true'
        OR coalesce(p.access_settings->>'partners', 'false') = 'true'
        OR coalesce(p.access_settings->>'fleet_ruter', 'false') = 'true'
        OR coalesce(p.access_settings->>'partners_admin', 'false') = 'true'
        OR lower(coalesce(d.name, '')) LIKE '%rute%'
      )
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

COMMENT ON FUNCTION public.notify_mavi_partner_internal IS
  'Interne MAVI-varsler om ruter/samarbeid — kun ruteansvarlige, ikke alle ledere.';

-- Maks én daglig oppsummering per bedrift (unngår hundrevis av duplikater i kø).
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
    IF EXISTS (
      SELECT 1
      FROM public.email_outbox o
      WHERE o.company_id = rec.company_id
        AND o.category = 'partner_route_pending'
        AND o.created_at > now() - interval '20 hours'
    ) THEN
      CONTINUE;
    END IF;

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

GRANT EXECUTE ON FUNCTION public.profile_is_mavi_route_ops_recipient(UUID, UUID) TO authenticated;
