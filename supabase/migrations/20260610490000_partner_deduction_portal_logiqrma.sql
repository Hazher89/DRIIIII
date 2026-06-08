-- Bot/Trekk: eksponer LogiqRMA-felter i bil-eierportalen.

DROP FUNCTION IF EXISTS public.list_partner_deduction_cases_portal(UUID, INT);

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
  logiqrma_case_number TEXT,
  voucher_number TEXT,
  logistics_description TEXT,
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
    c.logiqrma_case_number, c.voucher_number, c.logistics_description,
    (SELECT count(*) FROM public.partner_deduction_evidence e WHERE e.case_id = c.id) AS evidence_count
  FROM public.partner_deduction_cases c
  JOIN public.partners p ON p.id = c.partner_id
  WHERE c.deleted_at IS NULL
    AND c.partner_id = coalesce(
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

GRANT EXECUTE ON FUNCTION public.list_partner_deduction_cases_portal(UUID, INT) TO authenticated, service_role;
