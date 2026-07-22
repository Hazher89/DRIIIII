-- Hurtigere firmavis arkiv for bilkontroll.
CREATE INDEX IF NOT EXISTS idx_pvi_company_inspected
  ON public.partner_vehicle_inspections(company_id, inspected_at DESC);

CREATE INDEX IF NOT EXISTS idx_pvi_company_partner_inspected
  ON public.partner_vehicle_inspections(company_id, partner_id, inspected_at DESC);
