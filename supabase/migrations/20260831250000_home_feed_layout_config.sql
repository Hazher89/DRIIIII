-- Avansert layout for forside-innhold (størrelse, tekst, farger, app/web).

ALTER TABLE public.company_home_feed_items
  ADD COLUMN IF NOT EXISTS layout_config JSONB NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.company_home_feed_items.layout_config IS
  'Visuell layout: størrelse, tekstposisjon, farger, media-fit — per app/web.';
