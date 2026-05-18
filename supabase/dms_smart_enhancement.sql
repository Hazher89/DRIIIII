-- DMS smart mapper: beskrivelse, passord, privat, stjernemerk filer
ALTER TABLE public.dms_folders
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS password_hash TEXT,
  ADD COLUMN IF NOT EXISTS is_private BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.dms_files
  ADD COLUMN IF NOT EXISTS is_starred BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.dms_folders.password_hash IS 'SHA-256 av mappepassord (klient hasher før lagring)';
COMMENT ON COLUMN public.dms_folders.is_private IS 'Kun eksplisitt delte brukere + admin ser mappen';
