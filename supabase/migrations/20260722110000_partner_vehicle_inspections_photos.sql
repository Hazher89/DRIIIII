-- Bilder vedlagt bilkontroll (kamera / opplasting)
ALTER TABLE public.partner_vehicle_inspections
  ADD COLUMN IF NOT EXISTS photo_paths JSONB NOT NULL DEFAULT '[]'::JSONB;
