-- Truck-maler, kompetansekurs, ansattfiler (kjør etter equipment_service_book.sql)

-- ── Utstyr: truck-type og kontrollmal ───────────────────────────────────────
ALTER TABLE public.equipment
  ADD COLUMN IF NOT EXISTS truck_subtype TEXT
    CHECK (truck_subtype IS NULL OR truck_subtype IN ('fork', 'clamp', 'other'));

ALTER TABLE public.equipment
  ADD COLUMN IF NOT EXISTS truck_checklist_data JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.equipment
  ADD COLUMN IF NOT EXISTS control_enabled BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE public.equipment
  ADD COLUMN IF NOT EXISTS internal_number TEXT;

COMMENT ON COLUMN public.equipment.truck_subtype IS 'fork=gaffeltruck, clamp=klemtruck';
COMMENT ON COLUMN public.equipment.truck_checklist_data IS 'Utfylt daglig/periodisk kontrollmal (JSON)';

-- ── Kompetansekurs (bedriftskatalog) ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.competence_courses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  category TEXT DEFAULT 'generelt',
  requires_expiry BOOLEAN NOT NULL DEFAULT true,
  default_validity_months INTEGER DEFAULT 60,
  is_mandatory BOOLEAN NOT NULL DEFAULT false,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (company_id, name)
);

CREATE INDEX IF NOT EXISTS idx_competence_courses_company
  ON public.competence_courses(company_id);

ALTER TABLE public.competence_courses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS competence_courses_select ON public.competence_courses;
CREATE POLICY competence_courses_select ON public.competence_courses
  FOR SELECT USING (
    company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS competence_courses_write ON public.competence_courses;
CREATE POLICY competence_courses_write ON public.competence_courses
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.company_id = competence_courses.company_id
        AND p.role IN ('admin', 'superadmin', 'leder')
    )
  );

-- ── Dokumenter: ansatt-synlighet + kurskobling ───────────────────────────────
ALTER TABLE public.documents
  ADD COLUMN IF NOT EXISTS employee_visible BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.documents
  ADD COLUMN IF NOT EXISTS course_id UUID REFERENCES public.competence_courses(id) ON DELETE SET NULL;

ALTER TABLE public.documents
  ADD COLUMN IF NOT EXISTS tags TEXT[] DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_documents_course ON public.documents(course_id);
CREATE INDEX IF NOT EXISTS idx_documents_employee_visible ON public.documents(employee_visible);

-- Ansatt ser egne dokumenter der employee_visible = true
DROP POLICY IF EXISTS documents_select_own ON public.documents;
CREATE POLICY documents_select_own ON public.documents
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.company_id = documents.company_id
        AND p.role IN ('admin', 'superadmin', 'leder')
    )
  );

-- Superadmin/leder kan sette inn dokument for ansatt
CREATE OR REPLACE FUNCTION public.upsert_employee_document(
  p_user_id UUID,
  p_company_id UUID,
  p_document_type TEXT,
  p_title TEXT,
  p_file_url TEXT,
  p_file_name TEXT DEFAULT NULL,
  p_file_size INTEGER DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_expires_at DATE DEFAULT NULL,
  p_employee_visible BOOLEAN DEFAULT false,
  p_course_id UUID DEFAULT NULL,
  p_tags TEXT[] DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_role TEXT;
BEGIN
  SELECT role::text INTO v_role FROM public.profiles WHERE id = auth.uid();
  IF v_role NOT IN ('superadmin', 'admin', 'leder') THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_user_id AND company_id = p_company_id
  ) THEN
    RAISE EXCEPTION 'Ugyldig ansatt';
  END IF;

  INSERT INTO public.documents (
    user_id, company_id, document_type, title, description,
    file_url, file_name, file_size, expires_at,
    uploaded_by, employee_visible, course_id, tags
  ) VALUES (
    p_user_id, p_company_id, p_document_type::document_type, p_title, p_description,
    p_file_url, p_file_name, p_file_size, p_expires_at,
    auth.uid(), COALESCE(p_employee_visible, false), p_course_id, COALESCE(p_tags, '{}')
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- Seed standard truck-kurs for nye bedrifter (valgfritt – app har også hardkodede)
CREATE OR REPLACE FUNCTION public.seed_default_competence_courses(p_company_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.competence_courses (company_id, name, category, is_mandatory, sort_order)
  VALUES
    (p_company_id, 'Truckførerbevis', 'truck', true, 10),
    (p_company_id, 'Maskinførerbevis', 'maskin', false, 20),
    (p_company_id, 'Førerkort', 'kjøretøy', false, 30),
    (p_company_id, 'Førstehjelp', 'hms', true, 40),
    (p_company_id, 'HMS-kurs', 'hms', true, 50),
    (p_company_id, 'Arbeid i høyden', 'hms', false, 60),
    (p_company_id, 'Klemtruck / spesialtruck', 'truck', false, 70)
  ON CONFLICT (company_id, name) DO NOTHING;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_employee_document TO authenticated;
GRANT EXECUTE ON FUNCTION public.seed_default_competence_courses TO authenticated;
