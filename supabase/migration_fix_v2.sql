-- Legg til is_starred kolonne i dms_files
ALTER TABLE public.dms_files ADD COLUMN IF NOT EXISTS is_starred BOOLEAN DEFAULT false;

-- Tillat created_by å være NULL i migration-elementer for å unngå krasj
ALTER TABLE public.dms_folders ALTER COLUMN created_by DROP NOT NULL;
ALTER TABLE public.dms_files ALTER COLUMN created_by DROP NOT NULL;
