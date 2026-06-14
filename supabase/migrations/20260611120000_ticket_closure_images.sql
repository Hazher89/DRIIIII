-- Lukkebilder på avvik: gjenbruker eksisterende kolonner (ingen ny tabell/RPC).
-- Sikrer at annotated_image_urls finnes i miljøer som kun har kjørt migrasjoner.

ALTER TABLE public.tickets
  ADD COLUMN IF NOT EXISTS annotated_image_urls TEXT[] DEFAULT '{}';

COMMENT ON COLUMN public.tickets.annotated_image_urls IS
  'Bilder lastet opp ved lukking/behandling (saksbehandler), separat fra image_urls (innmelder).';
