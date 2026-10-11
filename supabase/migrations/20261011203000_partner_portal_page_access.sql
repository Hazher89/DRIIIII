-- Per partnerbedrift: hvilke sider partner-innloggingen skal vise.
-- Tomt objekt = alt på. Eksplisitt false skjuler siden uten nytt app-bygg.

ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS portal_access jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.partners.portal_access IS
  'Sider i partner-portalen. Mangler nøkkel = på. false = skjult for alle innlogginger i bedriften.';
