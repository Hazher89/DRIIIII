-- Utleie av bil: MAVI tildeler låntaker, bileier dokumenterer og sender, MAVI godkjenner.

CREATE TABLE IF NOT EXISTS public.vehicle_rentals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  lender_partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  borrower_partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  partner_vehicle_id UUID NOT NULL REFERENCES public.partner_vehicles(id) ON DELETE CASCADE,
  registration_number TEXT,
  vehicle_make TEXT,
  unit_code TEXT,
  rental_start DATE,
  rental_end DATE,
  status TEXT NOT NULL DEFAULT 'pending_owner'
    CHECK (status IN ('pending_owner', 'pending_mavi', 'approved', 'rejected', 'cancelled')),
  agreement_accepted_at TIMESTAMPTZ,
  owner_submitted_at TIMESTAMPTZ,
  approved_at TIMESTAMPTZ,
  approved_by UUID REFERENCES public.profiles(id),
  rejected_at TIMESTAMPTZ,
  rejection_reason TEXT,
  fuel_level TEXT,
  odometer_km INT,
  owner_comment TEXT,
  photos JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_vehicle_rentals_company ON public.vehicle_rentals(company_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_rentals_lender ON public.vehicle_rentals(lender_partner_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_rentals_borrower ON public.vehicle_rentals(borrower_partner_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_rentals_vehicle ON public.vehicle_rentals(partner_vehicle_id);
CREATE INDEX IF NOT EXISTS idx_vehicle_rentals_status ON public.vehicle_rentals(status);
CREATE INDEX IF NOT EXISTS idx_vehicle_rentals_approved_at ON public.vehicle_rentals(approved_at DESC NULLS LAST);

COMMENT ON TABLE public.vehicle_rentals IS
  'Bilutleie mellom samarbeidspartnere. Bileier dokumenterer med 6 bilder; MAVI godkjenner.';

ALTER TABLE public.vehicle_rentals ENABLE ROW LEVEL SECURITY;

-- ── RLS: intern MAVI + bileier (låner) + låntaker (kun godkjente) ─────────────
DROP POLICY IF EXISTS vehicle_rentals_select ON public.vehicle_rentals;
CREATE POLICY vehicle_rentals_select ON public.vehicle_rentals FOR SELECT USING (
  (
    company_id IN (
      SELECT company_id FROM public.profiles
      WHERE id = auth.uid() AND company_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x
      WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  )
  OR (
    lender_partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.partner_id IS NOT NULL
        AND p.partner_vehicle_id IS NULL
    )
  )
  OR (
    borrower_partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.partner_id IS NOT NULL
        AND p.partner_vehicle_id IS NULL
    )
    AND status = 'approved'
  )
);

DROP POLICY IF EXISTS vehicle_rentals_insert ON public.vehicle_rentals;
CREATE POLICY vehicle_rentals_insert ON public.vehicle_rentals FOR INSERT WITH CHECK (
  company_id IN (
    SELECT company_id FROM public.profiles
    WHERE id = auth.uid() AND company_id IS NOT NULL
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.profiles x
    WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
  )
);

DROP POLICY IF EXISTS vehicle_rentals_update ON public.vehicle_rentals;
CREATE POLICY vehicle_rentals_update ON public.vehicle_rentals FOR UPDATE USING (
  (
    company_id IN (
      SELECT company_id FROM public.profiles
      WHERE id = auth.uid() AND company_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x
      WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  )
  OR (
    lender_partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.partner_id IS NOT NULL
        AND p.partner_vehicle_id IS NULL
    )
    AND status IN ('pending_owner', 'pending_mavi')
  )
);

GRANT SELECT, INSERT, UPDATE ON public.vehicle_rentals TO authenticated;

-- ── SMS til bileiere ved ny utleie ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_vehicle_rental_owner_sms(p_rental_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  borrower_name TEXT;
  msg TEXT;
  owner_rec RECORD;
  n INT := 0;
BEGIN
  SELECT
    vr.*,
    p.name AS lender_name
  INTO r
  FROM public.vehicle_rentals vr
  JOIN public.partners p ON p.id = vr.lender_partner_id
  WHERE vr.id = p_rental_id;

  IF r IS NULL THEN
    RETURN 0;
  END IF;

  SELECT name INTO borrower_name FROM public.partners WHERE id = r.borrower_partner_id;

  msg := 'Ny bilutleie i DriftPro: '
    || coalesce(r.unit_code, 'bil')
    || coalesce(' (' || nullif(trim(r.registration_number), '') || ')', '')
    || ' skal lånes ut til '
    || coalesce(borrower_name, 'samarbeidspartner')
    || '. Logg inn som bil-eier, les avtalen, ta 6 bilder og send til godkjenning.';

  FOR owner_rec IN
    SELECT DISTINCT public.normalize_phone_no(src.phone) AS phone
    FROM (
      SELECT p.phone
      FROM public.partners p
      WHERE p.id = r.lender_partner_id AND p.phone IS NOT NULL
      UNION ALL
      SELECT ppa.phone
      FROM public.partner_portal_accounts ppa
      WHERE ppa.partner_id = r.lender_partner_id
        AND ppa.is_active = true
        AND coalesce(ppa.account_kind, case when ppa.partner_vehicle_id is null then 'owner' else 'driver' end) = 'owner'
        AND ppa.phone IS NOT NULL
      UNION ALL
      SELECT pr.phone
      FROM public.partner_portal_accounts ppa
      JOIN public.profiles pr ON pr.id = ppa.profile_id
      WHERE ppa.partner_id = r.lender_partner_id
        AND ppa.is_active = true
        AND coalesce(ppa.account_kind, case when ppa.partner_vehicle_id is null then 'owner' else 'driver' end) = 'owner'
        AND pr.phone IS NOT NULL
      UNION ALL
      SELECT pr.phone
      FROM public.profiles pr
      WHERE pr.partner_id = r.lender_partner_id
        AND pr.partner_vehicle_id IS NULL
        AND pr.phone IS NOT NULL
    ) src
    WHERE public.normalize_phone_no(src.phone) IS NOT NULL
  LOOP
    IF owner_rec.phone IS NOT NULL THEN
      PERFORM public.queue_sms(
        r.company_id,
        owner_rec.phone,
        msg,
        'vehicle_rental',
        'vehicle_rentals',
        r.id
      );
      n := n + 1;
    END IF;
  END LOOP;

  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_vehicle_rental_owner_sms(UUID) TO authenticated;
