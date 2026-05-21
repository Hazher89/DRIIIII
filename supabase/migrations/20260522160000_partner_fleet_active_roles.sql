-- Aktive/inaktive partnere og MAVI-biler + flere biltyper per enhet.

ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE public.partner_vehicles
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS fleet_roles TEXT[] NOT NULL DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_partners_company_active
  ON public.partners(company_id, is_active);

CREATE INDEX IF NOT EXISTS idx_partner_vehicles_active
  ON public.partner_vehicles(company_id, is_active);

COMMENT ON COLUMN public.partners.is_active IS 'false = skjules i ruteplanlegger og kalender';
COMMENT ON COLUMN public.partner_vehicles.is_active IS 'false = skjules i ruteplanlegger og kalender';
COMMENT ON COLUMN public.partner_vehicles.fleet_roles IS 'tjenestebil | enmannsbil | 2mannsbil | intern (kan være flere)';
