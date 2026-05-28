-- Superadmin nødstopp: slett bilutleieavtale permanent og frigjør blokkering.
CREATE OR REPLACE FUNCTION public.superadmin_force_delete_vehicle_rental(
  p_rental_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role public.user_role;
BEGIN
  v_role := public.get_user_role();
  IF v_role IS DISTINCT FROM 'superadmin'::public.user_role THEN
    RAISE EXCEPTION 'Kun superadmin kan slette bilutleieavtaler';
  END IF;

  DELETE FROM public.vehicle_rentals
  WHERE id = p_rental_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fant ikke utleieavtale';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.superadmin_force_delete_vehicle_rental(UUID, TEXT) TO authenticated;
