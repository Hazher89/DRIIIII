-- Synk partners.email → portal (varsler) + trigger ved oppdatering.

CREATE OR REPLACE FUNCTION public.sync_partner_notification_emails(
  p_company_id UUID DEFAULT NULL
)
RETURNS TABLE (
  partners_touched INT,
  portal_emails_filled INT,
  partner_emails_filled INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  n_partners INT := 0;
  n_portal INT := 0;
  n_partner INT := 0;
BEGIN
  SELECT company_id INTO v_company_id
  FROM public.profiles WHERE id = auth.uid();

  IF v_company_id IS NULL AND p_company_id IS NULL THEN
    RAISE EXCEPTION 'Ingen firmatilknytning';
  END IF;

  IF p_company_id IS NOT NULL THEN
    IF v_company_id IS NOT NULL AND p_company_id IS DISTINCT FROM v_company_id THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role::text = 'superadmin'
      ) THEN
        RAISE EXCEPTION 'Ingen tilgang til annet firma';
      END IF;
    END IF;
    v_company_id := p_company_id;
  END IF;

  WITH active AS (
    SELECT p.id, trim(lower(p.email)) AS pe
    FROM public.partners p
    WHERE p.company_id = v_company_id AND p.is_active = true
  ),
  upd_portal AS (
    UPDATE public.partner_portal_accounts ppa
    SET login_email = a.pe, updated_at = now()
    FROM active a
    WHERE ppa.partner_id = a.id
      AND ppa.is_active = true
      AND a.pe <> ''
      AND coalesce(trim(ppa.login_email), '') = ''
    RETURNING ppa.id
  ),
  upd_partner AS (
    UPDATE public.partners p
    SET email = sub.portal_email
    FROM (
      SELECT ppa.partner_id, min(trim(lower(ppa.login_email))) AS portal_email
      FROM public.partner_portal_accounts ppa
      JOIN active a ON a.id = ppa.partner_id
      WHERE ppa.is_active = true AND coalesce(trim(ppa.login_email), '') <> ''
      GROUP BY ppa.partner_id
    ) sub
    WHERE p.id = sub.partner_id AND coalesce(trim(p.email), '') = ''
    RETURNING p.id
  )
  SELECT
    (SELECT count(*)::int FROM active),
    (SELECT count(*)::int FROM upd_portal),
    (SELECT count(*)::int FROM upd_partner)
  INTO n_partners, n_portal, n_partner;

  partners_touched := n_partners;
  portal_emails_filled := n_portal;
  partner_emails_filled := n_partner;
  RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_partner_notification_emails(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.trg_sync_partner_email_to_portal()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  em TEXT;
BEGIN
  em := trim(lower(coalesce(NEW.email, '')));
  IF em = '' THEN
    RETURN NEW;
  END IF;
  UPDATE public.partner_portal_accounts
  SET login_email = em, updated_at = now()
  WHERE partner_id = NEW.id
    AND is_active = true
    AND coalesce(account_kind, 'owner') IN ('owner', 'admin')
    AND (
      coalesce(trim(login_email), '') = ''
      OR lower(trim(login_email)) IS DISTINCT FROM em
    );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_partner_email_to_portal ON public.partners;
CREATE TRIGGER trg_sync_partner_email_to_portal
  AFTER INSERT OR UPDATE OF email ON public.partners
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_sync_partner_email_to_portal();

-- Utvid e-postvarsler: alle aktive portal-kontoer med e-post (ikke bare owner/admin).
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
    SELECT trim(lower(login_email)) AS email
    FROM public.partner_portal_accounts
    WHERE partner_id = p_partner_id AND is_active = true
      AND coalesce(login_email, '') <> ''
  LOOP
    v_email := rec.email;
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
