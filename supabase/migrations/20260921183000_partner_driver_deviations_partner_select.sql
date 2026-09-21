-- Partner eier/ansatt kan lese sjåføravvik for egen partner (ikke MAVI-only).

DROP POLICY IF EXISTS partner_driver_deviations_partner_select
  ON public.partner_driver_deviations;
CREATE POLICY partner_driver_deviations_partner_select
  ON public.partner_driver_deviations
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.partner_portal_accounts ppa
      WHERE ppa.profile_id = auth.uid()
        AND coalesce(ppa.is_active, true)
        AND ppa.partner_id = partner_driver_deviations.partner_id
        AND coalesce(ppa.account_kind, 'driver') IN ('owner', 'staff')
    )
  );
