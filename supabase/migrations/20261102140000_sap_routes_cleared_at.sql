-- Tidsstempel for «Tøm alt»: aldri hent SAP-ruter mottatt før dette.
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS sap_routes_cleared_at TIMESTAMPTZ;

COMMENT ON COLUMN public.companies.sap_routes_cleared_at IS
  'Når brukeren sist trykket Tøm på SAP-kø. Graph/Hent skal kun ta mail mottatt ETTER dette.';
