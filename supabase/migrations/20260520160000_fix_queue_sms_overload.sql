-- Fiks PGRST203: PostgREST kan ikke velge mellom to queue_sms-overloads.
-- Kjør i Supabase SQL Editor (prosjekt ksnnyccthotjbrmgjgdc).

-- Fjern gammel 6-parameter-versjon (void).
DROP FUNCTION IF EXISTS public.queue_sms(uuid, text, text, text, text, uuid);

-- Én kanonisk funksjon (returnerer outbox-id).
CREATE OR REPLACE FUNCTION public.queue_sms(
  p_company_id UUID,
  p_to_phone TEXT,
  p_message TEXT,
  p_category TEXT DEFAULT NULL,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id UUID DEFAULT NULL,
  p_to_user_id UUID DEFAULT NULL,
  p_triggered_by_user_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized TEXT;
  new_id UUID;
BEGIN
  normalized := public.normalize_phone_no(p_to_phone);
  IF normalized IS NULL THEN
    RETURN NULL;
  END IF;
  IF p_message IS NULL OR length(trim(p_message)) = 0 THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.sms_outbox (
    company_id, to_phone, message, category, reference_type, reference_id,
    to_user_id, triggered_by_user_id
  ) VALUES (
    p_company_id,
    normalized,
    left(trim(p_message), 1071),
    p_category,
    p_reference_type,
    p_reference_id,
    p_to_user_id,
    COALESCE(p_triggered_by_user_id, auth.uid())
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.queue_sms(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.queue_sms(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID, UUID) TO authenticated, service_role;
