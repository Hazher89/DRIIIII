-- Lagret PDF-rapport per bilkontroll (kan lastes ned når som helst)
ALTER TABLE public.partner_vehicle_inspections
  ADD COLUMN IF NOT EXISTS pdf_storage_path TEXT;

CREATE INDEX IF NOT EXISTS idx_pvi_pdf_path
  ON public.partner_vehicle_inspections(partner_id)
  WHERE pdf_storage_path IS NOT NULL;
