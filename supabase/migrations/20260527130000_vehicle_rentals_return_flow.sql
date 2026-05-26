-- Retur av lånt bil, MAVI-kommentarer og utvidet status.

ALTER TABLE public.vehicle_rentals
  ADD COLUMN IF NOT EXISTS mavi_checkout_comment TEXT,
  ADD COLUMN IF NOT EXISTS mavi_return_comment TEXT,
  ADD COLUMN IF NOT EXISTS return_photos JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS return_fuel_level TEXT,
  ADD COLUMN IF NOT EXISTS return_odometer_km INT,
  ADD COLUMN IF NOT EXISTS return_comment TEXT,
  ADD COLUMN IF NOT EXISTS return_submitted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS return_approved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS return_approved_by UUID REFERENCES public.profiles(id);

ALTER TABLE public.vehicle_rentals DROP CONSTRAINT IF EXISTS vehicle_rentals_status_check;
ALTER TABLE public.vehicle_rentals ADD CONSTRAINT vehicle_rentals_status_check
  CHECK (status IN (
    'pending_owner',
    'pending_mavi',
    'approved',
    'pending_return_mavi',
    'returned',
    'rejected',
    'cancelled'
  ));

CREATE INDEX IF NOT EXISTS idx_vehicle_rentals_active_vehicle
  ON public.vehicle_rentals(partner_vehicle_id)
  WHERE status IN ('pending_owner', 'pending_mavi', 'approved', 'pending_return_mavi');

-- Låntaker ser aktive og arkiverte utleier
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
    AND status IN ('approved', 'pending_return_mavi', 'returned')
  )
);

DROP POLICY IF EXISTS vehicle_rentals_update ON public.vehicle_rentals;
CREATE POLICY vehicle_rentals_update ON public.vehicle_rentals FOR UPDATE USING (
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
    AND status IN ('pending_owner', 'pending_mavi')
  )
  OR (
    borrower_partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.partner_id IS NOT NULL
        AND p.partner_vehicle_id IS NULL
    )
    AND status = 'approved'
  )
);

COMMENT ON COLUMN public.vehicle_rentals.mavi_checkout_comment IS
  'MAVI-kommentar ved godkjenning av utleie (arkiveres).';
COMMENT ON COLUMN public.vehicle_rentals.mavi_return_comment IS
  'MAVI-kommentar ved godkjenning av retur (arkiveres).';
