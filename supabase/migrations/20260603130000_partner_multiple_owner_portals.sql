-- Tillat flere aktive bil-eier-portaler per samarbeidspartner.
DROP INDEX IF EXISTS public.idx_partner_portal_owner_unique;

-- Unikt brukernavn og innloggings-e-post per aktiv konto (uavhengig av type).
CREATE UNIQUE INDEX IF NOT EXISTS idx_partner_portal_username_active
  ON public.partner_portal_accounts (lower(username))
  WHERE is_active = true;

CREATE UNIQUE INDEX IF NOT EXISTS idx_partner_portal_login_email_active
  ON public.partner_portal_accounts (lower(login_email))
  WHERE is_active = true;
