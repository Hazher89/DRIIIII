-- Partner-innlogging fra web (anon): brukernavn → e-post
GRANT EXECUTE ON FUNCTION public.resolve_partner_login_email(text) TO anon, authenticated;
