-- GDPR: bil-eier ser kun egen bedrift; sjåfør kun egne ruter.
-- Kjør etter partners_schema.sql og route_ack_and_email_notifications.sql

-- ── Ruter: sjåfør kun egen bil, bil-eier alle biler på partner ───────────────
DROP POLICY IF EXISTS "partner_route_shares_select" ON public.partner_route_shares;
CREATE POLICY "partner_route_shares_select" ON public.partner_route_shares FOR SELECT USING (
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
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.partner_id IS NOT NULL
        AND p.partner_vehicle_id IS NULL
    )
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
    AND partner_vehicle_id IN (
      SELECT p.partner_vehicle_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
  )
);

DROP POLICY IF EXISTS "partner_route_shares_update" ON public.partner_route_shares;
CREATE POLICY "partner_route_shares_update" ON public.partner_route_shares FOR UPDATE USING (
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
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.partner_id IS NOT NULL
        AND p.partner_vehicle_id IS NULL
    )
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
    AND partner_vehicle_id IN (
      SELECT p.partner_vehicle_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
  )
);

-- ── Dokumenter: bil-eier ser owner_visible; sjåfør kun driver_visible ──────
DROP POLICY IF EXISTS "partner_documents_select" ON public.partner_documents;
CREATE POLICY "partner_documents_select" ON public.partner_documents FOR SELECT USING (
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
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.partner_id IS NOT NULL
        AND p.partner_vehicle_id IS NULL
    )
    AND COALESCE(owner_visible, true) = true
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
    AND COALESCE(driver_visible, false) = true
  )
);

-- ── Møter: kun bil-eier portal (ikke sjåfør) ─────────────────────────────────
DROP POLICY IF EXISTS "partner_meetings_select" ON public.partner_meetings;
CREATE POLICY "partner_meetings_select" ON public.partner_meetings FOR SELECT USING (
  partner_id IN (
    SELECT pr.id FROM public.partners pr
    WHERE pr.company_id IN (
      SELECT company_id FROM public.profiles WHERE id = auth.uid()
    )
  )
  OR partner_id IN (
    SELECT p.partner_id FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.partner_id IS NOT NULL
      AND p.partner_vehicle_id IS NULL
  )
);

-- ── Bilkontroll: bil-eier lese egen bedrift ──────────────────────────────────
DROP POLICY IF EXISTS pvi_select ON public.partner_vehicle_inspections;
CREATE POLICY pvi_select ON public.partner_vehicle_inspections FOR SELECT USING (
  (
    company_id IN (
      SELECT p.company_id FROM public.profiles p WHERE p.id = auth.uid()
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x
      WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  )
  OR partner_id IN (
    SELECT p.partner_id FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.partner_id IS NOT NULL
      AND p.partner_vehicle_id IS NULL
  )
);

-- ── Partnere: portal ser kun egen bedrift ────────────────────────────────────
DROP POLICY IF EXISTS "partners_select" ON public.partners;
CREATE POLICY "partners_select" ON public.partners FOR SELECT USING (
  company_id IN (
    SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL
  )
  OR id IN (
    SELECT partner_id FROM public.profiles
    WHERE id = auth.uid() AND partner_id IS NOT NULL
  )
);

-- ── Kjøretøy: bil-eier alle på partner; sjåfør kun egen ───────────────────────
DROP POLICY IF EXISTS "partner_vehicles_select" ON public.partner_vehicles;
CREATE POLICY "partner_vehicles_select" ON public.partner_vehicles FOR SELECT USING (
  (
    company_id IN (
      SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NULL AND p.partner_id IS NOT NULL
    )
  )
  OR id IN (
    SELECT p.partner_vehicle_id FROM public.profiles p
    WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
  )
);
