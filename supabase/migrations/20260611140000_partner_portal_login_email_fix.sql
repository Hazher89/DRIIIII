-- partners.email = varslings-e-post. login_email = teknisk Auth-innlogging (@portal.driftpro.no).
-- Tidligere trigger overskrev login_email med partners.email → duplikat ved flere bil-eiere
-- eller når samme Gmail allerede var i bruk globalt.

CREATE OR REPLACE FUNCTION public.trg_sync_partner_email_to_portal()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Ikke synkroniser partners.email inn i login_email — det er separate formål.
  RETURN NEW;
END;
$$;

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
  upd_partner AS (
    UPDATE public.partners p
    SET email = sub.portal_email
    FROM (
      SELECT ppa.partner_id, min(trim(lower(ppa.login_email))) AS portal_email
      FROM public.partner_portal_accounts ppa
      JOIN active a ON a.id = ppa.partner_id
      WHERE ppa.is_active = true
        AND coalesce(trim(ppa.login_email), '') <> ''
        AND trim(lower(ppa.login_email)) NOT LIKE '%@portal.driftpro.no'
      GROUP BY ppa.partner_id
    ) sub
    WHERE p.id = sub.partner_id AND coalesce(trim(p.email), '') = ''
    RETURNING p.id
  )
  SELECT
    (SELECT count(*)::int FROM active),
    0,
    (SELECT count(*)::int FROM upd_partner)
  INTO n_partners, n_portal, n_partner;

  partners_touched := n_partners;
  portal_emails_filled := n_portal;
  partner_emails_filled := n_partner;
  RETURN NEXT;
END;
$$;
