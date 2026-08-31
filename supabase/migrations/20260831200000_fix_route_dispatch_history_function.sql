-- Reparer get_partner_route_dispatch_history når CREATE OR REPLACE feiler pga. nytt returformat.
-- Kjør denne hvis du får: cannot change return type of existing function (42P13)

DROP FUNCTION IF EXISTS public.get_partner_route_dispatch_history(UUID, DATE, DATE);

CREATE OR REPLACE FUNCTION public.get_partner_route_dispatch_history(
  p_company_id UUID,
  p_from_date DATE,
  p_to_date DATE DEFAULT NULL
)
RETURNS TABLE (
  share_id UUID,
  partner_id UUID,
  partner_name TEXT,
  unit_code TEXT,
  registration_number TEXT,
  title TEXT,
  share_date DATE,
  dispatch_status TEXT,
  shift_name TEXT,
  route_start_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  sent_by UUID,
  sent_by_name TEXT,
  ack_status TEXT,
  ack_at TIMESTAMPTZ,
  ack_by UUID,
  ack_by_name TEXT,
  pdf_opened_at TIMESTAMPTZ,
  pdf_opened_by UUID,
  pdf_opened_by_name TEXT,
  pdf_open_count INT,
  notify_channels TEXT[],
  customer_count INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_to DATE := coalesce(p_to_date, p_from_date);
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles me
    WHERE me.id = auth.uid()
      AND me.company_id = p_company_id
      AND me.is_active = true
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    prs.id AS share_id,
    prs.partner_id,
    p.name AS partner_name,
    pv.unit_code,
    pv.registration_number,
    prs.title,
    prs.share_date,
    prs.dispatch_status,
    fsd.name AS shift_name,
    prs.route_start_at,
    prs.sent_at,
    prs.sent_by,
    sender.full_name AS sent_by_name,
    prs.ack_status,
    prs.ack_at,
    prs.ack_by,
    acker.full_name AS ack_by_name,
    prs.pdf_opened_at,
    prs.pdf_opened_by,
    opener.full_name AS pdf_opened_by_name,
    coalesce(prs.pdf_open_count, 0) AS pdf_open_count,
    coalesce(prs.notify_channels, ARRAY['app','sms','email']::text[]) AS notify_channels,
    prs.customer_count
  FROM public.partner_route_shares prs
  LEFT JOIN public.partners p ON p.id = prs.partner_id
  LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
  LEFT JOIN public.fleet_shift_definitions fsd ON fsd.id = prs.shift_id
  LEFT JOIN public.profiles sender ON sender.id = prs.sent_by
  LEFT JOIN public.profiles opener ON opener.id = prs.pdf_opened_by
  LEFT JOIN public.profiles acker ON acker.id = prs.ack_by
  WHERE prs.company_id = p_company_id
    AND prs.share_date >= p_from_date
    AND prs.share_date <= v_to
    AND coalesce(prs.dispatch_status, 'sent') IN ('sent', 'registered', 'staged')
  ORDER BY
    coalesce(prs.sent_at, prs.route_start_at, prs.created_at) DESC,
    prs.share_date DESC,
    pv.unit_code ASC NULLS LAST;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_partner_route_dispatch_history(UUID, DATE, DATE) TO authenticated;
