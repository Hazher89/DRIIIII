-- Fast route PDF text search (bilag / FO / FU / free text).
-- Leading-wildcard ILIKE on large pdf_search_text was timing out (~22k rows).

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS partner_route_shares_pdf_search_trgm_idx
  ON public.partner_route_shares
  USING gin (pdf_search_text gin_trgm_ops)
  WHERE pdf_search_text IS NOT NULL AND length(pdf_search_text) > 0;

CREATE OR REPLACE FUNCTION public.search_partner_route_pdf_text(
  p_company_id uuid,
  p_query text,
  p_limit int DEFAULT 40,
  p_from_day date DEFAULT NULL,
  p_to_day date DEFAULT NULL
)
RETURNS SETOF public.partner_route_shares
LANGUAGE sql
STABLE
SECURITY INVOKER
SET statement_timeout TO '8s'
AS $$
  SELECT s.*
  FROM public.partner_route_shares s
  WHERE s.company_id = p_company_id
    AND s.pdf_search_text IS NOT NULL
    AND length(trim(p_query)) >= 2
    AND s.pdf_search_text ILIKE ('%' || trim(p_query) || '%')
    AND (p_from_day IS NULL OR s.share_date >= p_from_day)
    AND (p_to_day IS NULL OR s.share_date <= p_to_day)
  ORDER BY s.share_date DESC NULLS LAST
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 40), 120));
$$;

GRANT EXECUTE ON FUNCTION public.search_partner_route_pdf_text(uuid, text, int, date, date)
  TO authenticated, service_role;
