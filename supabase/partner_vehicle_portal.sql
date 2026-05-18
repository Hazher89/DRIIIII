-- MAVI per bil: portal, telefon, starttid på rute, fri-forespørsler
-- Kjør etter partner_fleet_portal.sql og partner_route_dispatch_search.sql

ALTER TABLE public.partner_vehicles
  ADD COLUMN IF NOT EXISTS phone TEXT;

ALTER TABLE public.partner_portal_accounts
  ADD COLUMN IF NOT EXISTS partner_vehicle_id UUID REFERENCES public.partner_vehicles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS phone TEXT;

CREATE INDEX IF NOT EXISTS idx_partner_portal_vehicle ON public.partner_portal_accounts(partner_vehicle_id);

ALTER TABLE public.partner_route_shares
  ADD COLUMN IF NOT EXISTS route_start_at TIMESTAMPTZ;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS partner_vehicle_id UUID REFERENCES public.partner_vehicles(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.partner_fri_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  partner_vehicle_id UUID REFERENCES public.partner_vehicles(id) ON DELETE SET NULL,
  requested_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  request_date DATE NOT NULL,
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  review_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_partner_fri_company ON public.partner_fri_requests(company_id, status);
CREATE INDEX IF NOT EXISTS idx_partner_fri_vehicle ON public.partner_fri_requests(partner_vehicle_id);

ALTER TABLE public.partner_fri_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "partner_fri_select" ON public.partner_fri_requests;
CREATE POLICY "partner_fri_select" ON public.partner_fri_requests FOR SELECT USING (
  company_id IN (SELECT p.company_id FROM public.profiles p WHERE p.id = auth.uid())
  OR partner_id IN (SELECT p.partner_id FROM public.profiles p WHERE p.id = auth.uid() AND p.partner_id IS NOT NULL)
);

DROP POLICY IF EXISTS "partner_fri_insert" ON public.partner_fri_requests;
CREATE POLICY "partner_fri_insert" ON public.partner_fri_requests FOR INSERT WITH CHECK (
  partner_id IN (SELECT p.partner_id FROM public.profiles p WHERE p.id = auth.uid() AND p.partner_id IS NOT NULL)
  OR (
    company_id IN (SELECT p.company_id FROM public.profiles p WHERE p.id = auth.uid())
    AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
  )
);

DROP POLICY IF EXISTS "partner_fri_update" ON public.partner_fri_requests;
CREATE POLICY "partner_fri_update" ON public.partner_fri_requests FOR UPDATE USING (
  company_id IN (SELECT p.company_id FROM public.profiles p WHERE p.id = auth.uid())
  AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
);

-- Bootstrap inkluderer bil
CREATE OR REPLACE FUNCTION public.resolve_partner_portal_bootstrap()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  em TEXT := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  r JSONB;
BEGIN
  IF em IS NULL OR em = '' THEN
    RETURN NULL;
  END IF;
  SELECT jsonb_build_object(
    'partner_id', ppa.partner_id,
    'company_id', ppa.company_id,
    'partner_vehicle_id', ppa.partner_vehicle_id
  )
  INTO r
  FROM public.partner_portal_accounts ppa
  WHERE lower(ppa.login_email) = em
    AND ppa.is_active = true
  LIMIT 1;
  RETURN r;
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_partner_bootstrap_to_profile()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  em TEXT := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  p UUID;
  c UUID;
  vid UUID;
BEGIN
  IF uid IS NULL OR em IS NULL OR em = '' THEN
    RETURN;
  END IF;
  SELECT ppa.partner_id, ppa.company_id, ppa.partner_vehicle_id
  INTO p, c, vid
  FROM public.partner_portal_accounts ppa
  WHERE lower(ppa.login_email) = em
    AND ppa.is_active = true
  LIMIT 1;
  IF p IS NULL THEN
    RETURN;
  END IF;
  UPDATE public.profiles
  SET
    partner_id = p,
    company_id = coalesce(company_id, c),
    partner_vehicle_id = vid,
    role = 'samarbeidspartner'::public.user_role,
    is_onboarded = true,
    is_approved = true
  WHERE id = uid;
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_partner_profile_from_portal()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  em TEXT := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  p UUID;
  c UUID;
  vid UUID;
  fn TEXT;
  ph TEXT;
BEGIN
  IF uid IS NULL OR em = '' THEN
    RETURN;
  END IF;
  SELECT ppa.partner_id, ppa.company_id, ppa.partner_vehicle_id, ppa.phone
  INTO p, c, vid, ph
  FROM public.partner_portal_accounts ppa
  WHERE lower(ppa.login_email) = em
    AND ppa.is_active = true
  LIMIT 1;
  IF p IS NULL THEN
    RETURN;
  END IF;
  fn := coalesce(nullif(trim(split_part(em, '@', 1)), ''), 'Partner');
  INSERT INTO public.profiles (
    id, email, full_name, role, company_id, partner_id, partner_vehicle_id, phone,
    is_onboarded, is_approved, is_active
  )
  VALUES (
    uid, em, fn, 'samarbeidspartner'::public.user_role, c, p, vid, ph,
    true, true, true
  )
  ON CONFLICT (id) DO UPDATE SET
    email = excluded.email,
    partner_id = excluded.partner_id,
    company_id = coalesce(public.profiles.company_id, excluded.company_id),
    partner_vehicle_id = excluded.partner_vehicle_id,
    phone = coalesce(excluded.phone, public.profiles.phone),
    role = 'samarbeidspartner'::public.user_role,
    is_onboarded = true,
    is_approved = true,
    is_active = true;
END;
$$;

-- SMS ved sendt rute til bil-telefon
CREATE OR REPLACE FUNCTION public.notify_partner_route_assigned_sms(p_route_share_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  shift_name TEXT;
  msg TEXT;
  n INT := 0;
BEGIN
  SELECT prs.*, pv.phone AS vehicle_phone, pv.unit_code,
         ppa.phone AS portal_phone
  INTO r
  FROM public.partner_route_shares prs
  LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
  LEFT JOIN public.partner_portal_accounts ppa ON ppa.partner_vehicle_id = pv.id AND ppa.is_active = true
  WHERE prs.id = p_route_share_id;

  IF r IS NULL THEN
    RETURN 0;
  END IF;

  SELECT name INTO shift_name FROM public.fleet_shift_definitions WHERE id = r.shift_id;

  msg := 'Ny rute tildelt ' || coalesce(r.unit_code, '') ||
    case when shift_name is not null then ' · Skift: ' || shift_name else '' end ||
    case when r.route_start_at is not null then
      ' · Start ' || to_char(r.route_start_at at time zone 'Europe/Oslo', 'DD.MM HH24:MI')
    else '' end ||
    '. Logg inn i DriftPro partner for PDF og aksept.';

  IF coalesce(r.vehicle_phone, r.portal_phone) IS NOT NULL THEN
    PERFORM public.queue_sms(
      r.company_id,
      coalesce(r.vehicle_phone, r.portal_phone),
      msg,
      'partner_route',
      'partner_route_shares',
      r.id
    );
    n := 1;
  END IF;
  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_partner_route_assigned_sms(UUID) TO authenticated, service_role;
