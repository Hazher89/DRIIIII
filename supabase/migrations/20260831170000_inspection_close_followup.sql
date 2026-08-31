-- Lukk bilkontroll-oppfølging med stempel og kommentar (MAVI-ansatte).

ALTER TABLE public.partner_vehicle_inspections
  ADD COLUMN IF NOT EXISTS follow_up_action_notes TEXT,
  ADD COLUMN IF NOT EXISTS follow_up_closed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.close_partner_vehicle_inspection_followup(
  p_inspection_id UUID,
  p_action_notes TEXT,
  p_next_inspection_at DATE DEFAULT NULL
)
RETURNS public.partner_vehicle_inspections
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.partner_vehicle_inspections%ROWTYPE;
  v_notes TEXT := trim(coalesce(p_action_notes, ''));
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND partner_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Kun MAVI-ansatte kan lukke oppfølging';
  END IF;

  IF v_notes = '' THEN
    RAISE EXCEPTION 'Beskriv hva som er gjort';
  END IF;

  SELECT * INTO v_row
  FROM public.partner_vehicle_inspections
  WHERE id = p_inspection_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kontroll ikke funnet';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND company_id = v_row.company_id
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  UPDATE public.partner_vehicle_inspections
  SET
    follow_up_acknowledged_at = now(),
    follow_up_action_notes = v_notes,
    follow_up_closed_by = auth.uid(),
    next_inspection_at = coalesce(p_next_inspection_at, next_inspection_at)
  WHERE id = p_inspection_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.close_partner_vehicle_inspection_followup(UUID, TEXT, DATE) TO authenticated;
