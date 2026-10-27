-- Allow recreating portal logins after deactivate: inactive rows kept username/email
-- forever under the old global unique indexes, which blocked insert/reactivate.
-- Active uniqueness is already enforced by idx_partner_portal_*_active.

DROP INDEX IF EXISTS public.uq_partner_portal_username;
DROP INDEX IF EXISTS public.uq_partner_portal_email;

CREATE UNIQUE INDEX IF NOT EXISTS idx_partner_portal_username_active
  ON public.partner_portal_accounts (lower(username))
  WHERE is_active = true;

CREATE UNIQUE INDEX IF NOT EXISTS idx_partner_portal_login_email_active
  ON public.partner_portal_accounts (lower(login_email))
  WHERE is_active = true;
