-- Daglig skiftplan per MAVI-sjåfør (Ruteoversikt 2026 / Excel-paritet).
CREATE TABLE IF NOT EXISTS public.mavi_driver_day_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  partner_vehicle_id UUID NOT NULL REFERENCES public.partner_vehicles(id) ON DELETE CASCADE,
  assignment_date DATE NOT NULL,
  shift_id UUID NOT NULL REFERENCES public.fleet_shift_definitions(id) ON DELETE CASCADE,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (partner_vehicle_id, assignment_date)
);

CREATE INDEX IF NOT EXISTS idx_mavi_day_assign_company_date
  ON public.mavi_driver_day_assignments (company_id, assignment_date);

CREATE INDEX IF NOT EXISTS idx_mavi_day_assign_vehicle
  ON public.mavi_driver_day_assignments (partner_vehicle_id);

ALTER TABLE public.mavi_driver_day_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "mavi_day_assign_select" ON public.mavi_driver_day_assignments;
CREATE POLICY "mavi_day_assign_select" ON public.mavi_driver_day_assignments
  FOR SELECT USING (
    company_id IN (
      SELECT p.company_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.company_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x
      WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  );

DROP POLICY IF EXISTS "mavi_day_assign_manage" ON public.mavi_driver_day_assignments;
CREATE POLICY "mavi_day_assign_manage" ON public.mavi_driver_day_assignments
  FOR ALL USING (
    company_id IN (
      SELECT p.company_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.company_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x
      WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  )
  WITH CHECK (
    company_id IN (
      SELECT p.company_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.company_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x
      WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  );
