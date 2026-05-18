-- Partner & kjøretøy utvidelse (kjør etter partner_fleet_portal.sql)

ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS has_transport_license BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS transport_license_count INTEGER NOT NULL DEFAULT 0;

ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS employee_count INTEGER;

ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS audit_status TEXT NOT NULL DEFAULT 'ukjent'
    CHECK (audit_status IN ('ukjent', 'planlagt', 'ok', 'avvik', 'utlopt'));

ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS audit_plate TEXT;

ALTER TABLE public.partner_vehicles
  ADD COLUMN IF NOT EXISTS model_year INTEGER;

ALTER TABLE public.partner_vehicles
  ADD COLUMN IF NOT EXISTS payload_kg INTEGER;

ALTER TABLE public.partner_vehicles
  ADD COLUMN IF NOT EXISTS eu_last_at DATE;

ALTER TABLE public.partner_vehicles
  ADD COLUMN IF NOT EXISTS eu_next_at DATE;

ALTER TABLE public.partner_vehicles
  ADD COLUMN IF NOT EXISTS eu_approved BOOLEAN;

ALTER TABLE public.partner_vehicles
  ADD COLUMN IF NOT EXISTS image_urls TEXT[] NOT NULL DEFAULT '{}';

ALTER TABLE public.partner_vehicles
  ADD COLUMN IF NOT EXISTS vegvesen_snapshot JSONB;

ALTER TABLE public.partner_vehicles
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_partner_vehicles_eu_next
  ON public.partner_vehicles(eu_next_at);

-- Varsle partner om møte via SMS
CREATE OR REPLACE FUNCTION public.notify_partner_meeting_sms(
  p_partner_id UUID,
  p_message TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone TEXT;
  v_company UUID;
  v_count INTEGER := 0;
BEGIN
  SELECT phone, company_id INTO v_phone, v_company
  FROM public.partners WHERE id = p_partner_id;
  IF v_phone IS NULL OR length(trim(v_phone)) < 8 THEN
    RETURN 0;
  END IF;
  PERFORM public.queue_sms(
    v_company,
    v_phone,
    left(p_message, 1600),
    'partner_meeting',
    'partner',
    p_partner_id,
    NULL,
    NULL
  );
  RETURN 1;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_partner_meeting_sms TO authenticated;
