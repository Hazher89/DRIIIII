-- Bilkontroll per samarbeidspartner (mal, avvik, oppfølging)
-- Kjør i Supabase SQL Editor

CREATE TABLE IF NOT EXISTS public.partner_vehicle_inspections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  partner_vehicle_id UUID REFERENCES public.partner_vehicles(id) ON DELETE SET NULL,
  registration_number TEXT,
  unit_code TEXT,
  inspected_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  inspected_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  checklist JSONB NOT NULL DEFAULT '{}'::JSONB,
  has_deviation BOOLEAN NOT NULL DEFAULT FALSE,
  deviation_notes TEXT,
  deviation_assignee UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  next_inspection_at DATE,
  follow_up_due_at DATE,
  follow_up_acknowledged_at TIMESTAMPTZ,
  is_archived BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pvi_partner ON public.partner_vehicle_inspections(partner_id, inspected_at DESC);
CREATE INDEX IF NOT EXISTS idx_pvi_follow_up ON public.partner_vehicle_inspections(follow_up_due_at)
  WHERE has_deviation = TRUE AND follow_up_acknowledged_at IS NULL;

ALTER TABLE public.partner_vehicle_inspections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pvi_select ON public.partner_vehicle_inspections;
CREATE POLICY pvi_select ON public.partner_vehicle_inspections FOR SELECT USING (
  company_id IN (SELECT p.company_id FROM public.profiles p WHERE p.id = auth.uid())
  OR partner_id IN (SELECT p.partner_id FROM public.profiles p WHERE p.id = auth.uid() AND p.partner_id IS NOT NULL)
);

DROP POLICY IF EXISTS pvi_manage ON public.partner_vehicle_inspections;
CREATE POLICY pvi_manage ON public.partner_vehicle_inspections FOR ALL USING (
  company_id IN (SELECT p.company_id FROM public.profiles p WHERE p.id = auth.uid())
  AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
) WITH CHECK (
  company_id IN (SELECT p.company_id FROM public.profiles p WHERE p.id = auth.uid())
  AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
);
