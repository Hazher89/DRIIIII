-- ============================================================
-- DriftPro – Samarbeidspartnere (bedrifter, dokumenter, møter, ruter)
-- Kjør etter eksisterende schema. Utvider user_role og profiles.
-- ============================================================

-- Ny rolle: portal-brukere for eksterne samarbeidspartnere
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON e.enumtypid = t.oid
    JOIN pg_namespace n ON t.typnamespace = n.oid
    WHERE n.nspname = 'public' AND t.typname = 'user_role'
      AND e.enumlabel = 'samarbeidspartner'
  ) THEN
    ALTER TYPE public.user_role ADD VALUE 'samarbeidspartner';
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS public.partners (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    org_number TEXT,
    name TEXT NOT NULL,
    trade_name TEXT,
    owner_name TEXT,
    phone TEXT,
    email TEXT,
    address TEXT,
    postal_code TEXT,
    city TEXT,
    country TEXT DEFAULT 'NO',
    notes TEXT,
    vehicle_count_registered INTEGER DEFAULT 0,
    vehicle_max_payload_kg INTEGER,
    eu_approved BOOLEAN,
    brreg_snapshot JSONB,
    last_meeting_at TIMESTAMPTZ,
    next_meeting_at TIMESTAMPTZ,
    last_audit_at DATE,
    next_audit_at DATE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_partners_company ON public.partners(company_id);
CREATE INDEX IF NOT EXISTS idx_partners_org ON public.partners(org_number);

CREATE TABLE IF NOT EXISTS public.partner_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    storage_path TEXT,
    file_name TEXT,
    mime_type TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_partner_documents_partner ON public.partner_documents(partner_id);

CREATE TABLE IF NOT EXISTS public.partner_meetings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    scheduled_at TIMESTAMPTZ NOT NULL,
    is_direct BOOLEAN DEFAULT TRUE,
    location TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.partner_route_shares (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT,
    pdf_storage_path TEXT NOT NULL,
    share_date DATE NOT NULL DEFAULT (CURRENT_DATE),
    is_daily_share BOOLEAN DEFAULT FALSE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_partner_routes_partner ON public.partner_route_shares(partner_id);

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS partner_id UUID REFERENCES public.partners(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_profiles_partner ON public.profiles(partner_id);

-- RLS
ALTER TABLE public.partners ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_route_shares ENABLE ROW LEVEL SECURITY;

-- Hjelp: finn min bedrift og evt. partner for innlogget bruker
-- Policy: ansatte i samme selskap ser alle partnere for selskapet.
-- Partner-brukere ser kun sin egen partner-rad.

DROP POLICY IF EXISTS "partners_select" ON public.partners;
CREATE POLICY "partners_select" ON public.partners FOR SELECT
USING (
  company_id IN (SELECT p.company_id FROM public.profiles p WHERE p.id = auth.uid() AND p.company_id IS NOT NULL)
  OR id IN (SELECT p.partner_id FROM public.profiles p WHERE p.id = auth.uid() AND p.partner_id IS NOT NULL)
);

DROP POLICY IF EXISTS "partners_insert" ON public.partners;
CREATE POLICY "partners_insert" ON public.partners FOR INSERT
WITH CHECK (
  company_id IN (SELECT p.company_id FROM public.profiles p WHERE p.id = auth.uid() AND p.company_id IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
);

DROP POLICY IF EXISTS "partners_update" ON public.partners;
CREATE POLICY "partners_update" ON public.partners FOR UPDATE
USING (
  company_id IN (SELECT p.company_id FROM public.profiles p WHERE p.id = auth.uid() AND p.company_id IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
);

DROP POLICY IF EXISTS "partners_delete" ON public.partners;
CREATE POLICY "partners_delete" ON public.partners FOR DELETE
USING (
  company_id IN (SELECT p.company_id FROM public.profiles p WHERE p.id = auth.uid() AND p.company_id IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
);

-- Dokumenter
DROP POLICY IF EXISTS "partner_documents_all" ON public.partner_documents;
DROP POLICY IF EXISTS "partner_documents_select" ON public.partner_documents;
DROP POLICY IF EXISTS "partner_documents_insert" ON public.partner_documents;
DROP POLICY IF EXISTS "partner_documents_update" ON public.partner_documents;
DROP POLICY IF EXISTS "partner_documents_delete" ON public.partner_documents;
CREATE POLICY "partner_documents_select" ON public.partner_documents FOR SELECT
USING (
  partner_id IN (SELECT pr.id FROM public.partners pr WHERE pr.company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid()))
  OR partner_id IN (SELECT partner_id FROM public.profiles WHERE id = auth.uid() AND partner_id IS NOT NULL)
);

CREATE POLICY "partner_documents_insert" ON public.partner_documents FOR INSERT
WITH CHECK (
  company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
);

CREATE POLICY "partner_documents_update" ON public.partner_documents FOR UPDATE
USING (
  company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
);

CREATE POLICY "partner_documents_delete" ON public.partner_documents FOR DELETE
USING (
  company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
);

-- Møter
DROP POLICY IF EXISTS "partner_meetings_select" ON public.partner_meetings;
CREATE POLICY "partner_meetings_select" ON public.partner_meetings FOR SELECT
USING (
  partner_id IN (SELECT pr.id FROM public.partners pr WHERE pr.company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid()))
  OR partner_id IN (SELECT partner_id FROM public.profiles WHERE id = auth.uid() AND partner_id IS NOT NULL)
);

DROP POLICY IF EXISTS "partner_meetings_insert" ON public.partner_meetings;
CREATE POLICY "partner_meetings_insert" ON public.partner_meetings FOR INSERT
WITH CHECK (
  partner_id IN (SELECT pr.id FROM public.partners pr WHERE pr.company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL))
  AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
);

DROP POLICY IF EXISTS "partner_meetings_update" ON public.partner_meetings;
CREATE POLICY "partner_meetings_update" ON public.partner_meetings FOR UPDATE
USING (
  partner_id IN (SELECT pr.id FROM public.partners pr WHERE pr.company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL))
  AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
);

DROP POLICY IF EXISTS "partner_meetings_delete" ON public.partner_meetings;
CREATE POLICY "partner_meetings_delete" ON public.partner_meetings FOR DELETE
USING (
  partner_id IN (SELECT pr.id FROM public.partners pr WHERE pr.company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL))
  AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
);

-- Rutedeling PDF
DROP POLICY IF EXISTS "partner_route_shares_select" ON public.partner_route_shares;
CREATE POLICY "partner_route_shares_select" ON public.partner_route_shares FOR SELECT
USING (
  partner_id IN (SELECT pr.id FROM public.partners pr WHERE pr.company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid()))
  OR partner_id IN (SELECT partner_id FROM public.profiles WHERE id = auth.uid() AND partner_id IS NOT NULL)
);

DROP POLICY IF EXISTS "partner_route_shares_insert" ON public.partner_route_shares;
CREATE POLICY "partner_route_shares_insert" ON public.partner_route_shares FOR INSERT
WITH CHECK (
  company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
);

DROP POLICY IF EXISTS "partner_route_shares_update" ON public.partner_route_shares;
CREATE POLICY "partner_route_shares_update" ON public.partner_route_shares FOR UPDATE
USING (
  company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
);

DROP POLICY IF EXISTS "partner_route_shares_delete" ON public.partner_route_shares;
CREATE POLICY "partner_route_shares_delete" ON public.partner_route_shares FOR DELETE
USING (
  company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
);
