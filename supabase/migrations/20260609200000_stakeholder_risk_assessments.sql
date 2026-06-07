-- Interessepart og risikovurdering (ISO 9001/14001 mal)

CREATE TABLE IF NOT EXISTS public.stakeholder_risk_assessments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  title text NOT NULL,
  assessment_year int,
  status text NOT NULL DEFAULT 'aktiv' CHECK (status IN ('aktiv', 'utkast', 'arkivert')),
  content jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_stakeholder_risk_assessments_company
  ON public.stakeholder_risk_assessments (company_id, updated_at DESC);

ALTER TABLE public.stakeholder_risk_assessments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS stakeholder_risk_select ON public.stakeholder_risk_assessments;
CREATE POLICY stakeholder_risk_select ON public.stakeholder_risk_assessments
  FOR SELECT USING (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS stakeholder_risk_insert ON public.stakeholder_risk_assessments;
CREATE POLICY stakeholder_risk_insert ON public.stakeholder_risk_assessments
  FOR INSERT WITH CHECK (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND created_by = auth.uid()
  );

DROP POLICY IF EXISTS stakeholder_risk_update ON public.stakeholder_risk_assessments;
CREATE POLICY stakeholder_risk_update ON public.stakeholder_risk_assessments
  FOR UPDATE USING (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS stakeholder_risk_delete ON public.stakeholder_risk_assessments;
CREATE POLICY stakeholder_risk_delete ON public.stakeholder_risk_assessments
  FOR DELETE USING (
    company_id = (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    AND (
      created_by = auth.uid()
      OR (SELECT role::text FROM public.profiles WHERE id = auth.uid()) IN ('admin', 'superadmin', 'leder')
    )
  );
