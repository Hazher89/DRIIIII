ALTER TABLE public.partner_route_shares
  ADD COLUMN IF NOT EXISTS customer_count INTEGER;

COMMENT ON COLUMN public.partner_route_shares.customer_count IS 'Antall kunder/stopp fra PDF ved publisering';
