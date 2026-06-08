-- Bot/Trekk: bilde/video-bevis lagret i Dropbox + synlig for bil-eier i portal.

CREATE TABLE IF NOT EXISTS public.partner_deduction_evidence (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id UUID NOT NULL REFERENCES public.partner_deduction_cases(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  storage_ref TEXT NOT NULL,
  storage_provider TEXT NOT NULL DEFAULT 'dropbox'
    CHECK (storage_provider IN ('dropbox', 'supabase')),
  file_name TEXT NOT NULL,
  mime_type TEXT,
  media_type TEXT NOT NULL DEFAULT 'image'
    CHECK (media_type IN ('image', 'video')),
  file_size_bytes BIGINT,
  dropbox_path TEXT,
  owner_visible BOOLEAN NOT NULL DEFAULT true,
  uploaded_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_partner_deduction_evidence_case
  ON public.partner_deduction_evidence (case_id, created_at);
CREATE INDEX IF NOT EXISTS idx_partner_deduction_evidence_partner
  ON public.partner_deduction_evidence (partner_id, created_at DESC);

ALTER TABLE public.partner_deduction_evidence ENABLE ROW LEVEL SECURITY;

-- Bil-eier og MAVI kan lese saker
DROP POLICY IF EXISTS partner_deduction_cases_select ON public.partner_deduction_cases;
CREATE POLICY partner_deduction_cases_select ON public.partner_deduction_cases
  FOR SELECT USING (
    company_id IN (
      SELECT company_id FROM public.profiles
      WHERE id = auth.uid() AND company_id IS NOT NULL
    )
    OR partner_id IN (
      SELECT partner_id FROM public.profiles
      WHERE id = auth.uid() AND partner_id IS NOT NULL
    )
  );

DROP POLICY IF EXISTS partner_deduction_evidence_select ON public.partner_deduction_evidence;
CREATE POLICY partner_deduction_evidence_select ON public.partner_deduction_evidence
  FOR SELECT USING (
    owner_visible = true
    AND (
      company_id IN (
        SELECT company_id FROM public.profiles
        WHERE id = auth.uid() AND company_id IS NOT NULL
      )
      OR partner_id IN (
        SELECT partner_id FROM public.profiles
        WHERE id = auth.uid() AND partner_id IS NOT NULL
      )
    )
  );

DROP POLICY IF EXISTS partner_deduction_evidence_insert ON public.partner_deduction_evidence;
CREATE POLICY partner_deduction_evidence_insert ON public.partner_deduction_evidence
  FOR INSERT WITH CHECK (
    company_id IN (
      SELECT company_id FROM public.profiles
      WHERE id = auth.uid() AND company_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x
      WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  );

CREATE OR REPLACE FUNCTION public.add_partner_deduction_evidence(
  p_case_id UUID,
  p_storage_ref TEXT,
  p_storage_provider TEXT,
  p_file_name TEXT,
  p_mime_type TEXT DEFAULT NULL,
  p_media_type TEXT DEFAULT 'image',
  p_file_size_bytes BIGINT DEFAULT NULL,
  p_dropbox_path TEXT DEFAULT NULL
)
RETURNS public.partner_deduction_evidence
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_case public.partner_deduction_cases%ROWTYPE;
  v_row public.partner_deduction_evidence%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_case FROM public.partner_deduction_cases WHERE id = p_case_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sak ikke funnet';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND company_id = v_case.company_id
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  INSERT INTO public.partner_deduction_evidence (
    case_id, company_id, partner_id,
    storage_ref, storage_provider, file_name, mime_type, media_type,
    file_size_bytes, dropbox_path, owner_visible, uploaded_by
  ) VALUES (
    v_case.id, v_case.company_id, v_case.partner_id,
    p_storage_ref, coalesce(nullif(p_storage_provider, ''), 'dropbox'),
    p_file_name, p_mime_type, coalesce(nullif(p_media_type, ''), 'image'),
    p_file_size_bytes, p_dropbox_path, true, auth.uid()
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_partner_deduction_evidence(
  p_case_id UUID
)
RETURNS SETOF public.partner_deduction_evidence
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT e.*
  FROM public.partner_deduction_evidence e
  JOIN public.partner_deduction_cases c ON c.id = e.case_id
  WHERE e.case_id = p_case_id
    AND e.owner_visible = true
    AND (
      c.company_id IN (
        SELECT company_id FROM public.profiles
        WHERE id = auth.uid() AND company_id IS NOT NULL
      )
      OR c.partner_id IN (
        SELECT partner_id FROM public.profiles
        WHERE id = auth.uid() AND partner_id IS NOT NULL
      )
    )
  ORDER BY e.created_at ASC;
$$;

DROP FUNCTION IF EXISTS public.list_partner_deduction_cases(UUID, TEXT, UUID, INT, INT);

CREATE OR REPLACE FUNCTION public.list_partner_deduction_cases(
  p_company_id UUID,
  p_status TEXT DEFAULT NULL,
  p_partner_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 200,
  p_offset INT DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  company_id UUID,
  partner_id UUID,
  partner_name TEXT,
  case_number TEXT,
  template_id TEXT,
  template_title TEXT,
  short_description TEXT,
  comment TEXT,
  amount_nok NUMERIC,
  status TEXT,
  created_by UUID,
  created_by_name TEXT,
  created_at TIMESTAMPTZ,
  notified_at TIMESTAMPTZ,
  sms_sent BOOLEAN,
  email_sent BOOLEAN,
  invoiced_at TIMESTAMPTZ,
  invoiced_by UUID,
  invoiced_by_name TEXT,
  evidence_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.id, c.company_id, c.partner_id, p.name AS partner_name,
    c.case_number, c.template_id, c.template_title, c.short_description, c.comment,
    c.amount_nok, c.status, c.created_by,
    cr.full_name AS created_by_name,
    c.created_at, c.notified_at, c.sms_sent, c.email_sent,
    c.invoiced_at, c.invoiced_by, inv.full_name AS invoiced_by_name,
    (SELECT count(*) FROM public.partner_deduction_evidence e WHERE e.case_id = c.id) AS evidence_count
  FROM public.partner_deduction_cases c
  JOIN public.partners p ON p.id = c.partner_id
  LEFT JOIN public.profiles cr ON cr.id = c.created_by
  LEFT JOIN public.profiles inv ON inv.id = c.invoiced_by
  WHERE c.company_id = p_company_id
    AND EXISTS (
      SELECT 1 FROM public.profiles pr
      WHERE pr.id = auth.uid() AND pr.company_id = p_company_id
    )
    AND (p_status IS NULL OR c.status = p_status)
    AND (p_partner_id IS NULL OR c.partner_id = p_partner_id)
  ORDER BY c.created_at DESC
  LIMIT greatest(p_limit, 1)
  OFFSET greatest(p_offset, 0);
$$;

CREATE OR REPLACE FUNCTION public.list_partner_deduction_cases_portal(
  p_partner_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 100
)
RETURNS TABLE (
  id UUID,
  company_id UUID,
  partner_id UUID,
  partner_name TEXT,
  case_number TEXT,
  template_id TEXT,
  template_title TEXT,
  short_description TEXT,
  comment TEXT,
  amount_nok NUMERIC,
  status TEXT,
  created_at TIMESTAMPTZ,
  notified_at TIMESTAMPTZ,
  sms_sent BOOLEAN,
  email_sent BOOLEAN,
  invoiced_at TIMESTAMPTZ,
  evidence_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.id, c.company_id, c.partner_id, p.name AS partner_name,
    c.case_number, c.template_id, c.template_title, c.short_description, c.comment,
    c.amount_nok, c.status, c.created_at, c.notified_at, c.sms_sent, c.email_sent,
    c.invoiced_at,
    (SELECT count(*) FROM public.partner_deduction_evidence e WHERE e.case_id = c.id) AS evidence_count
  FROM public.partner_deduction_cases c
  JOIN public.partners p ON p.id = c.partner_id
  WHERE c.partner_id = coalesce(
    p_partner_id,
    (SELECT partner_id FROM public.profiles WHERE id = auth.uid() AND partner_id IS NOT NULL LIMIT 1)
  )
  AND EXISTS (
    SELECT 1 FROM public.profiles pr
    WHERE pr.id = auth.uid()
      AND (pr.partner_id = c.partner_id OR pr.company_id = c.company_id)
  )
  ORDER BY c.created_at DESC
  LIMIT greatest(p_limit, 1);
$$;

GRANT EXECUTE ON FUNCTION public.add_partner_deduction_evidence TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_partner_deduction_evidence TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_partner_deduction_cases_portal TO authenticated, service_role;
