-- Isolering: partnerportal ser KUN eget partnerfirma — aldri andre partnere.
-- MAVI (uten portal-konto) kan fortsatt se hele bedriften.

DROP FUNCTION IF EXISTS public.list_partner_driver_deviations(UUID, TEXT, INT);
DROP FUNCTION IF EXISTS public.list_partner_driver_deviations(UUID, TEXT, INT, UUID);
DROP FUNCTION IF EXISTS public.search_partner_driver_deviations(UUID, TEXT);
DROP FUNCTION IF EXISTS public.search_partner_driver_deviations(UUID, TEXT, UUID);

CREATE OR REPLACE FUNCTION public.list_partner_driver_deviations(
  p_company_id UUID,
  p_query TEXT DEFAULT NULL,
  p_limit INT DEFAULT 50,
  p_partner_id UUID DEFAULT NULL
)
RETURNS SETOF public.partner_driver_deviations
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT d.*
  FROM public.partner_driver_deviations d
  WHERE d.company_id = p_company_id
    AND (
      CASE
        -- Partner (eier/sjåfør/ansatt): ALLTID kun egen partner — kan ikke se andre.
        WHEN EXISTS (
          SELECT 1
          FROM public.partner_portal_accounts ppa
          WHERE ppa.profile_id = auth.uid()
            AND coalesce(ppa.is_active, true)
            AND ppa.company_id = p_company_id
        ) THEN d.partner_id IN (
          SELECT ppa.partner_id
          FROM public.partner_portal_accounts ppa
          WHERE ppa.profile_id = auth.uid()
            AND coalesce(ppa.is_active, true)
            AND ppa.company_id = p_company_id
        )
        -- MAVI arbeidsgiver: valgfri partner-filter, ellers alle i bedriften.
        WHEN p_partner_id IS NOT NULL THEN d.partner_id = p_partner_id
        ELSE true
      END
    )
    AND (
      nullif(trim(p_query), '') IS NULL
      OR d.search_text ILIKE '%' || lower(trim(p_query)) || '%'
    )
  ORDER BY d.created_at DESC
  LIMIT least(greatest(coalesce(p_limit, 50), 1), 200);
$$;

CREATE OR REPLACE FUNCTION public.search_partner_driver_deviations(
  p_company_id UUID,
  p_query TEXT,
  p_partner_id UUID DEFAULT NULL
)
RETURNS SETOF public.partner_driver_deviations
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT d.*
  FROM public.partner_driver_deviations d
  WHERE d.company_id = p_company_id
    AND length(trim(coalesce(p_query, ''))) >= 2
    AND d.search_text ILIKE '%' || lower(trim(p_query)) || '%'
    AND (
      CASE
        WHEN EXISTS (
          SELECT 1
          FROM public.partner_portal_accounts ppa
          WHERE ppa.profile_id = auth.uid()
            AND coalesce(ppa.is_active, true)
            AND ppa.company_id = p_company_id
        ) THEN d.partner_id IN (
          SELECT ppa.partner_id
          FROM public.partner_portal_accounts ppa
          WHERE ppa.profile_id = auth.uid()
            AND coalesce(ppa.is_active, true)
            AND ppa.company_id = p_company_id
        )
        WHEN p_partner_id IS NOT NULL THEN d.partner_id = p_partner_id
        ELSE true
      END
    )
  ORDER BY d.created_at DESC
  LIMIT 25;
$$;

GRANT EXECUTE ON FUNCTION public.list_partner_driver_deviations(UUID, TEXT, INT, UUID)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.search_partner_driver_deviations(UUID, TEXT, UUID)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.list_partner_driver_deviations(UUID, TEXT, INT, UUID) IS
  'Lister sjåføravvik. Partnerportal hardt isolert til egen partner_id; MAVI ser hele company.';
