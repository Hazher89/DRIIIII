-- Robust visning for portalbrukere:
-- tillat også når brukeren er koblet via partner_portal_accounts (selv om profiles.partner_id avviker/mangler).
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
      -- Direkte partner-kobling på profilen.
      borrower_partner_id IN (
        SELECT p.partner_id FROM public.profiles p
        WHERE p.id = auth.uid()
          AND p.partner_id IS NOT NULL
      )
      -- Knyttet via portal-konto.
      OR EXISTS (
        SELECT 1
        FROM public.partner_portal_accounts ppa
        WHERE ppa.profile_id = auth.uid()
          AND ppa.is_active = true
          AND ppa.partner_id = vehicle_rentals.borrower_partner_id
      )
      -- Fallback: samme org.nr (håndterer duplikate partner-id-er).
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
