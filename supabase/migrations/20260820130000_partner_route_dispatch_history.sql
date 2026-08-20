-- Rutehistorikk: hvem sendte, når PDF ble åpnet/lest.

ALTER TABLE public.partner_route_shares
  ADD COLUMN IF NOT EXISTS sent_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS pdf_opened_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS pdf_opened_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS pdf_open_count INT NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.partner_route_shares.sent_by IS
  'Profil som publiserte/sendte ruten (dispatch_status = sent eller registered).';
COMMENT ON COLUMN public.partner_route_shares.pdf_opened_at IS
  'Første gang PDF ble åpnet/lest i DriftPro.';
COMMENT ON COLUMN public.partner_route_shares.pdf_opened_by IS
  'Profil som åpnet PDF første gang.';
COMMENT ON COLUMN public.partner_route_shares.pdf_open_count IS
  'Antall ganger PDF er åpnet.';

CREATE INDEX IF NOT EXISTS idx_partner_route_shares_sent_at
  ON public.partner_route_shares (company_id, sent_at DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_partner_route_shares_share_date_company
  ON public.partner_route_shares (company_id, share_date DESC);

-- Marker PDF åpnet (første + teller). Portal-sjåfør/eier og MAVI.
CREATE OR REPLACE FUNCTION public.mark_partner_route_pdf_opened(p_route_share_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  r public.partner_route_shares%ROWTYPE;
  first_open BOOLEAN := false;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  SELECT * INTO r FROM public.partner_route_shares WHERE id = p_route_share_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  -- Tilgang: egen bedrift (MAVI) eller portal-konto på partner/bil.
  IF NOT (
    EXISTS (
      SELECT 1 FROM public.profiles me
      WHERE me.id = uid
        AND me.company_id = r.company_id
        AND me.is_active = true
    )
    OR EXISTS (
      SELECT 1 FROM public.partner_portal_accounts ppa
      WHERE ppa.profile_id = uid
        AND ppa.is_active = true
        AND ppa.partner_id = r.partner_id
        AND (
          ppa.partner_vehicle_id IS NULL
          OR ppa.partner_vehicle_id = r.partner_vehicle_id
        )
    )
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'forbidden');
  END IF;

  IF r.pdf_opened_at IS NULL THEN
    first_open := true;
    UPDATE public.partner_route_shares
    SET
      pdf_opened_at = now(),
      pdf_opened_by = uid,
      pdf_open_count = greatest(coalesce(pdf_open_count, 0), 0) + 1
    WHERE id = p_route_share_id;
  ELSE
    UPDATE public.partner_route_shares
    SET pdf_open_count = coalesce(pdf_open_count, 0) + 1
    WHERE id = p_route_share_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'first_open', first_open,
    'pdf_opened_at', (SELECT pdf_opened_at FROM public.partner_route_shares WHERE id = p_route_share_id),
    'pdf_open_count', (SELECT pdf_open_count FROM public.partner_route_shares WHERE id = p_route_share_id)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_partner_route_pdf_opened(UUID) TO authenticated;

-- Historikk for MAVI: ruter for en dato (eller intervall), med avsender og lesestatus.
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
