-- Sjåfør per MAVI + skill reg-biler fra MAVI-enheter
-- Kjør i Supabase SQL Editor

ALTER TABLE public.partner_vehicles
  ADD COLUMN IF NOT EXISTS driver_name TEXT;

ALTER TABLE public.partner_vehicles
  ADD COLUMN IF NOT EXISTS vehicle_kind TEXT NOT NULL DEFAULT 'mavi';

COMMENT ON COLUMN public.partner_vehicles.vehicle_kind IS 'mavi | registration (kun reg.nr på bedriften)';

-- Eksisterende REG-* rader (hvis noen)
UPDATE public.partner_vehicles
SET vehicle_kind = 'registration'
WHERE upper(unit_code) LIKE 'REG-%'
  AND vehicle_kind = 'mavi';
