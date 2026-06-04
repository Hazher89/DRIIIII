-- partner_portal_accounts manglet updated_at; flere funksjoner/triggere bruker kolonnen.

ALTER TABLE public.partner_portal_accounts
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

UPDATE public.partner_portal_accounts
SET updated_at = coalesce(created_at, now())
WHERE updated_at IS NULL;

CREATE OR REPLACE FUNCTION public.trg_partner_portal_accounts_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS partner_portal_accounts_set_updated_at ON public.partner_portal_accounts;
CREATE TRIGGER partner_portal_accounts_set_updated_at
  BEFORE UPDATE ON public.partner_portal_accounts
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_partner_portal_accounts_set_updated_at();

COMMENT ON COLUMN public.partner_portal_accounts.updated_at IS
  'Sist endret; brukes av SMS/e-post-sync og sortering av portal-kontoer.';
