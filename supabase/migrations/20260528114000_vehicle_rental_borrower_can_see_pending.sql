-- Låntaker skal se avtalen med en gang den opprettes (ikke kun etter godkjenning).
DROP POLICY IF EXISTS vehicle_rentals_select ON public.vehicle_rentals;
CREATE POLICY vehicle_rentals_select ON public.vehicle_rentals FOR SELECT USING (
  (
    company_id IN (
      SELECT company_id FROM public.profiles
      WHERE id = auth.uid() AND company_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x
      WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  )
  OR (
    lender_partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.partner_id IS NOT NULL
        AND p.partner_vehicle_id IS NULL
    )
  )
  OR (
    borrower_partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.partner_id IS NOT NULL
        AND p.partner_vehicle_id IS NULL
    )
    AND status IN ('pending_owner', 'pending_mavi', 'approved', 'pending_return_mavi', 'returned', 'rejected')
  )
);
