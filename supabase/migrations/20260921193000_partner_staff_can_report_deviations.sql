-- Ansatt kan sende sjåføravvik (tilgang som ruter/stempling).
-- Bil-eier ser alle firmaets avvik under «Mine» med reporter_name.
-- MAVI/CCC/superadmin ser allerede via eksisterende select-policy.

ALTER TABLE public.partner_staff
  ADD COLUMN IF NOT EXISTS can_report_deviations boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.partner_staff.can_report_deviations IS
  'Når true: ansatt kan melde rute-/kundeavvik for partnerfirmaets biler.';

ALTER TABLE public.partner_driver_deviations
  ADD COLUMN IF NOT EXISTS reporter_name TEXT;

COMMENT ON COLUMN public.partner_driver_deviations.reporter_name IS
  'Visningsnavn for den som sendte avviket (sjåfør/ansatt/bil-eier).';

-- Backfill fra profiles.
UPDATE public.partner_driver_deviations d
SET reporter_name = COALESCE(NULLIF(TRIM(p.full_name), ''), 'Ukjent')
FROM public.profiles p
WHERE p.id = d.reported_by
  AND (d.reporter_name IS NULL OR TRIM(d.reporter_name) = '');

CREATE OR REPLACE FUNCTION public.partner_driver_deviations_set_search_text()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.search_text := lower(trim(both FROM concat_ws(
    ' ',
    coalesce(NEW.freight_unit, ''),
    coalesce(NEW.customer_ref, ''),
    coalesce(NEW.order_ref, ''),
    coalesce(NEW.customer_name, ''),
    coalesce(NEW.comment, ''),
    coalesce(NEW.reporter_name, '')
  )));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_partner_driver_deviations_search_text
  ON public.partner_driver_deviations;
CREATE TRIGGER trg_partner_driver_deviations_search_text
  BEFORE INSERT OR UPDATE OF freight_unit, customer_ref, order_ref,
    customer_name, comment, reporter_name
  ON public.partner_driver_deviations
  FOR EACH ROW EXECUTE FUNCTION public.partner_driver_deviations_set_search_text();

-- Oppdater search_text for eksisterende rader med reporter_name.
UPDATE public.partner_driver_deviations
SET comment = comment
WHERE reporter_name IS NOT NULL;

CREATE OR REPLACE FUNCTION public.partner_staff_set_can_report_deviations(
  p_staff_id uuid,
  p_enabled boolean
)
RETURNS public.partner_staff
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.partner_staff%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_staff FROM public.partner_staff WHERE id = p_staff_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ansatt ikke funnet';
  END IF;

  IF NOT public.partner_staff_can_manage(v_staff.partner_id, v_staff.company_id) THEN
    RAISE EXCEPTION 'Mangler tilgang';
  END IF;

  UPDATE public.partner_staff
  SET can_report_deviations = coalesce(p_enabled, false),
      updated_at = now()
  WHERE id = p_staff_id
  RETURNING * INTO v_staff;

  RETURN v_staff;
END;
$$;

GRANT EXECUTE ON FUNCTION public.partner_staff_set_can_report_deviations(uuid, boolean)
  TO authenticated;

DROP POLICY IF EXISTS partner_driver_deviations_staff_insert
  ON public.partner_driver_deviations;
CREATE POLICY partner_driver_deviations_staff_insert
  ON public.partner_driver_deviations
  FOR INSERT TO authenticated
  WITH CHECK (
    reported_by = auth.uid()
    AND partner_vehicle_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.partner_portal_accounts ppa
      JOIN public.partner_staff ps
        ON ps.profile_id = ppa.profile_id
       AND ps.partner_id = ppa.partner_id
       AND coalesce(ps.is_active, true)
       AND coalesce(ps.can_report_deviations, false)
      WHERE ppa.profile_id = auth.uid()
        AND coalesce(ppa.is_active, true)
        AND coalesce(ppa.account_kind, 'driver') = 'staff'
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
