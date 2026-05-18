-- HMS plattform: utstyr + indekser (kjør i Supabase SQL Editor)

CREATE TABLE IF NOT EXISTS public.equipment (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  brand TEXT,
  model TEXT,
  serial_number TEXT,
  status TEXT NOT NULL DEFAULT 'ok' CHECK (status IN ('ok', 'needsService', 'broken', 'retired')),
  last_service DATE,
  next_service DATE,
  assigned_to UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  image_urls TEXT[] DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_equipment_company ON public.equipment(company_id);
CREATE INDEX IF NOT EXISTS idx_equipment_status ON public.equipment(status);

ALTER TABLE public.equipment ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "equipment_company" ON public.equipment;
CREATE POLICY "equipment_company" ON public.equipment
  FOR ALL
  USING (company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid()))
  WITH CHECK (company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid()));
