-- Bilutleie: låntaker skal være valgt bedrift (ikke tvunget til MAVI).

DROP TRIGGER IF EXISTS vehicle_rentals_set_borrower ON public.vehicle_rentals;
DROP FUNCTION IF EXISTS public.trg_vehicle_rentals_set_borrower();

