-- Bil-eier kan melde ruteavvik for egne biler (samme tabell som sjåfør).

DROP POLICY IF EXISTS partner_driver_deviations_owner_insert
  ON public.partner_driver_deviations;
CREATE POLICY partner_driver_deviations_owner_insert
  ON public.partner_driver_deviations
  FOR INSERT TO authenticated
  WITH CHECK (
    reported_by = auth.uid()
    AND partner_vehicle_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.partner_portal_accounts ppa
      WHERE ppa.profile_id = auth.uid()
        AND coalesce(ppa.is_active, true)
        AND coalesce(ppa.account_kind, 'driver') = 'owner'
        AND ppa.company_id = partner_driver_deviations.company_id
        AND ppa.partner_id = partner_driver_deviations.partner_id
    )
    AND EXISTS (
      SELECT 1
      FROM public.partner_vehicles pv
      WHERE pv.id = partner_driver_deviations.partner_vehicle_id
        AND pv.partner_id = partner_driver_deviations.partner_id
    )
  );
