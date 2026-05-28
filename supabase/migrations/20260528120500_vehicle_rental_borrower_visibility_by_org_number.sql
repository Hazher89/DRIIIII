-- Vis låntaker-avtaler også når bedriften er registrert med annen partner-id,
-- men samme org.nr som innlogget portalbrukers partner.
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
    status IN ('pending_owner', 'pending_mavi', 'approved', 'pending_return_mavi', 'returned', 'rejected')
    AND (
      borrower_partner_id IN (
        SELECT p.partner_id FROM public.profiles p
        WHERE p.id = auth.uid()
          AND p.partner_id IS NOT NULL
      )
      OR EXISTS (
        SELECT 1
        FROM public.profiles me
        JOIN public.partners my_partner ON my_partner.id = me.partner_id
        JOIN public.partners borrower_partner ON borrower_partner.id = vehicle_rentals.borrower_partner_id
        WHERE me.id = auth.uid()
          AND me.partner_id IS NOT NULL
          AND nullif(trim(my_partner.org_number), '') IS NOT NULL
          AND nullif(trim(my_partner.org_number), '') = nullif(trim(borrower_partner.org_number), '')
      )
    )
  )
);
