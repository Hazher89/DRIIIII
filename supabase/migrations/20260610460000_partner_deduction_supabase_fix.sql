-- Bot/Trekk: reparasjoner etter første deploy (stats, Nico/superadmin, saksnr-lås, Dropbox-modul).

-- Dropbox: aktiver partner_deductions for eksisterende koblinger.
UPDATE public.company_dropbox_connections
SET storage_modules = coalesce(storage_modules, '{}'::jsonb) || '{"partner_deductions": true}'::jsonb,
    updated_at = now()
WHERE NOT (coalesce(storage_modules, '{}'::jsonb) ? 'partner_deductions');

ALTER TABLE public.company_dropbox_connections
  ALTER COLUMN storage_modules SET DEFAULT '{
    "routes": true,
    "tickets": true,
    "dms": true,
    "partners": true,
    "employees": true,
    "hms": true,
    "partner_deductions": true
  }'::jsonb;

CREATE OR REPLACE FUNCTION public.next_partner_deduction_case_number(p_company_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_seq INT;
BEGIN
  PERFORM pg_advisory_xact_lock(
    hashtext('partner_deduction_case_num:' || p_company_id::text || ':' || v_year)
  );

  SELECT count(*)::INT + 1 INTO v_seq
  FROM public.partner_deduction_cases
  WHERE company_id = p_company_id
    AND case_number LIKE 'BOT-' || v_year || '-%';

  RETURN 'BOT-' || v_year || '-' || lpad(v_seq::TEXT, 4, '0');
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_partner_deductions_invoiced(
  p_company_id UUID,
  p_case_ids UUID[]
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
  v_profile public.profiles%ROWTYPE;
  v_is_superadmin BOOLEAN := public.get_user_role() = 'superadmin'::public.user_role;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  IF NOT v_is_superadmin AND v_profile.company_id IS DISTINCT FROM p_company_id THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  IF NOT (
    v_is_superadmin
    OR coalesce(v_profile.employee_number, '') = '144'
    OR lower(v_profile.full_name) LIKE '%nicola%'
    OR lower(v_profile.full_name) LIKE '%nico%'
    OR lower(coalesce(v_profile.email, '')) LIKE '%nico%'
  ) THEN
    RAISE EXCEPTION 'Kun økonomi (Nico) kan markere som fakturert';
  END IF;

  UPDATE public.partner_deduction_cases
  SET status = 'invoiced',
      invoiced_at = now(),
      invoiced_by = auth.uid()
  WHERE company_id = p_company_id
    AND id = ANY(p_case_ids)
    AND status <> 'invoiced';

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_partner_deduction_stats(p_company_id UUID)
RETURNS TABLE (
  open_count BIGINT,
  invoiced_count BIGINT,
  open_amount NUMERIC,
  invoiced_amount NUMERIC,
  evidence_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    coalesce(agg.open_count, 0),
    coalesce(agg.invoiced_count, 0),
    coalesce(agg.open_amount, 0),
    coalesce(agg.invoiced_amount, 0),
    coalesce(ev.cnt, 0)
  FROM (
    SELECT 1
    FROM public.profiles pr
    WHERE pr.id = auth.uid() AND pr.company_id = p_company_id
  ) access_check
  LEFT JOIN LATERAL (
    SELECT
      count(*) FILTER (WHERE c.status <> 'invoiced') AS open_count,
      count(*) FILTER (WHERE c.status = 'invoiced') AS invoiced_count,
      coalesce(sum(c.amount_nok) FILTER (WHERE c.status <> 'invoiced'), 0) AS open_amount,
      coalesce(sum(c.amount_nok) FILTER (WHERE c.status = 'invoiced'), 0) AS invoiced_amount
    FROM public.partner_deduction_cases c
    WHERE c.company_id = p_company_id
  ) agg ON true
  LEFT JOIN LATERAL (
    SELECT count(*)::bigint AS cnt
    FROM public.partner_deduction_evidence e
    JOIN public.partner_deduction_cases c2 ON c2.id = e.case_id
    WHERE c2.company_id = p_company_id
  ) ev ON true;
$$;

GRANT EXECUTE ON FUNCTION public.next_partner_deduction_case_number(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_partner_deductions_invoiced TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_partner_deduction_stats(UUID) TO authenticated, service_role;
