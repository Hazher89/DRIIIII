-- count_partner_email_log: match list_partner_email_log filter params (p_sender, p_sort).

DROP FUNCTION IF EXISTS public.count_partner_email_log(
  TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, UUID
);

CREATE OR REPLACE FUNCTION public.count_partner_email_log(
  p_search TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_from_date TIMESTAMPTZ DEFAULT NULL,
  p_to_date TIMESTAMPTZ DEFAULT NULL,
  p_recipient TEXT DEFAULT NULL,
  p_sender TEXT DEFAULT NULL,
  p_partner_id UUID DEFAULT NULL,
  p_sort TEXT DEFAULT 'created_desc'
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c BIGINT;
BEGIN
  IF NOT public.user_can_view_partner_sms_log() THEN
    RETURN 0;
  END IF;

  SELECT count(*)::bigint INTO c
  FROM public.list_partner_email_log(
    1000000,
    0,
    p_search,
    p_category,
    p_status,
    p_from_date,
    p_to_date,
    p_recipient,
    p_sender,
    p_partner_id,
    p_sort
  );

  RETURN c;
END;
$$;

GRANT EXECUTE ON FUNCTION public.count_partner_email_log(
  TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, UUID, TEXT
) TO authenticated;
