-- DMS smart-kolonner (manglet på remote) + reparer feilaktig opprettede felles-mapper.

ALTER TABLE public.dms_folders
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS password_hash TEXT,
  ADD COLUMN IF NOT EXISTS is_private BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.dms_files
  ADD COLUMN IF NOT EXISTS is_starred BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.dms_folders.password_hash IS 'SHA-256 av mappepassord (klient hasher før lagring)';
COMMENT ON COLUMN public.dms_folders.is_private IS 'Kun eksplisitt delte brukere + admin ser mappen';

-- «Opplæring» opprettet 2026-06-07 fra Felles mapper uten is_shared_mavi pga. insert-fallback.
UPDATE public.dms_folders
SET is_shared_mavi = true
WHERE name = 'Opplæring'
  AND is_shared_mavi = false
  AND created_at >= '2026-06-07'::timestamptz;
