-- Partner login: trim username; still resolve active accounts only.
-- (Inactive usernames must be recreated via provision — intentional.)

CREATE OR REPLACE FUNCTION public.resolve_partner_login_email(p_username text)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT ppa.login_email
  FROM public.partner_portal_accounts ppa
  WHERE lower(trim(ppa.username)) = lower(trim(p_username))
    AND ppa.is_active = true
  LIMIT 1
$$;

GRANT EXECUTE ON FUNCTION public.resolve_partner_login_email(text) TO anon, authenticated;
