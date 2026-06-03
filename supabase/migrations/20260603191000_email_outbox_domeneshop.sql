-- Utgående e-post (Domeneshop SMTP / ikkesvar@driftpro.no)
-- Kjør etter route_ack_and_email_notifications.sql hvis den allerede er applied.

CREATE TABLE IF NOT EXISTS public.email_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
  to_email TEXT NOT NULL,
  subject TEXT NOT NULL,
  body TEXT NOT NULL,
  category TEXT,
  reference_type TEXT,
  reference_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at TIMESTAMPTZ,
  error_message TEXT,
  attempts INT NOT NULL DEFAULT 0
);

ALTER TABLE public.email_outbox
  ADD COLUMN IF NOT EXISTS attempts INT NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_email_outbox_unsent
  ON public.email_outbox (created_at)
  WHERE sent_at IS NULL AND attempts < 5;

CREATE INDEX IF NOT EXISTS idx_email_outbox_company_created
  ON public.email_outbox (company_id, created_at DESC);

ALTER TABLE public.email_outbox ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS email_outbox_service_only ON public.email_outbox;
CREATE POLICY email_outbox_service_only ON public.email_outbox
  FOR ALL USING (false) WITH CHECK (false);

DROP FUNCTION IF EXISTS public.queue_email(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, UUID);

CREATE OR REPLACE FUNCTION public.queue_email(
  p_company_id UUID,
  p_to_email TEXT,
  p_subject TEXT,
  p_body TEXT,
  p_category TEXT DEFAULT NULL,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_id UUID;
  v_email TEXT;
BEGIN
  v_email := trim(lower(coalesce(p_to_email, '')));
  IF v_email = '' OR position('@' IN v_email) < 2 THEN
    RETURN NULL;
  END IF;
  IF p_subject IS NULL OR length(trim(p_subject)) = 0 THEN
    RETURN NULL;
  END IF;
  IF p_body IS NULL OR length(trim(p_body)) = 0 THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.email_outbox (
    company_id, to_email, subject, body, category, reference_type, reference_id
  ) VALUES (
    p_company_id,
    v_email,
    left(trim(p_subject), 500),
    left(trim(p_body), 50000),
    p_category,
    p_reference_type,
    p_reference_id
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.queue_email(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.queue_email(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, UUID)
  TO authenticated, service_role;

COMMENT ON TABLE public.email_outbox IS 'Utgående varsel-e-post (Domeneshop SMTP via send-email-outbox)';
