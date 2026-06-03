-- Flagg per rute: om purring SMS/e-post er sendt (for badge i UI).

CREATE OR REPLACE FUNCTION public.get_partner_route_reminder_flags(p_share_ids UUID[])
RETURNS TABLE (
  share_id UUID,
  last_reminder_sms_at TIMESTAMPTZ,
  last_reminder_email_at TIMESTAMPTZ,
  reminder_sms_count INT,
  reminder_email_count INT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
BEGIN
  IF p_share_ids IS NULL OR cardinality(p_share_ids) = 0 THEN
    RETURN;
  END IF;

  SELECT company_id INTO v_company_id
  FROM public.profiles
  WHERE id = auth.uid();

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Ingen firmatilknytning';
  END IF;

  RETURN QUERY
  SELECT
    prs.id AS share_id,
    (
      SELECT max(o.sent_at)
      FROM public.sms_outbox o
      WHERE o.reference_id = prs.id
        AND o.category = 'partner_route_reminder'
        AND o.sent_at IS NOT NULL
    ) AS last_reminder_sms_at,
    (
      SELECT max(e.sent_at)
      FROM public.email_outbox e
      WHERE e.reference_id = prs.id
        AND e.category = 'partner_route_reminder'
        AND e.sent_at IS NOT NULL
    ) AS last_reminder_email_at,
    (
      SELECT count(*)::int
      FROM public.sms_outbox o
      WHERE o.reference_id = prs.id
        AND o.category = 'partner_route_reminder'
        AND o.sent_at IS NOT NULL
    ) AS reminder_sms_count,
    (
      SELECT count(*)::int
      FROM public.email_outbox e
      WHERE e.reference_id = prs.id
        AND e.category = 'partner_route_reminder'
        AND e.sent_at IS NOT NULL
    ) AS reminder_email_count
  FROM public.partner_route_shares prs
  WHERE prs.id = ANY(p_share_ids)
    AND prs.company_id = v_company_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_partner_route_reminder_flags(UUID[]) TO authenticated;
