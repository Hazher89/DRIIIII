-- Bil-eier vs MAVI-sjåfør portal-kontoer
-- Kjør etter partner_vehicle_portal.sql

ALTER TABLE public.partner_portal_accounts
  ADD COLUMN IF NOT EXISTS account_kind TEXT NOT NULL DEFAULT 'driver'
    CHECK (account_kind IN ('owner', 'driver'));

CREATE UNIQUE INDEX IF NOT EXISTS idx_partner_portal_owner_unique
  ON public.partner_portal_accounts(partner_id)
  WHERE account_kind = 'owner' AND is_active = true;

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
  RETURN public.queue_sms(p_company_id, p_phone, msg, 'partner_portal', 'partner_portal_accounts', NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_partner_portal_credentials_sms(UUID, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated, service_role;
