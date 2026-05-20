-- Transportløyver, utvidede partner-dokumenter og møte/audit-sporing
-- Kjør i Supabase SQL Editor etter partners_schema.sql

-- ── Transportløyver (flere per bedrift) ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.partner_transport_licenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    license_number TEXT NOT NULL,
    vehicle_plate TEXT,
    valid_from DATE,
    valid_to DATE,
    issuer TEXT,
    notes TEXT,
    document_path TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ptl_partner ON public.partner_transport_licenses(partner_id);

ALTER TABLE public.partner_transport_licenses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ptl_select ON public.partner_transport_licenses;
CREATE POLICY ptl_select ON public.partner_transport_licenses FOR SELECT USING (
    company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    OR partner_id IN (
        SELECT partner_id FROM public.profiles
        WHERE id = auth.uid() AND partner_id IS NOT NULL
    )
);

DROP POLICY IF EXISTS ptl_manage ON public.partner_transport_licenses;
CREATE POLICY ptl_manage ON public.partner_transport_licenses FOR ALL
USING (
    company_id IN (
        SELECT company_id FROM public.profiles
        WHERE id = auth.uid() AND company_id IS NOT NULL
    )
    AND NOT EXISTS (
        SELECT 1 FROM public.profiles x
        WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
)
WITH CHECK (
    company_id IN (
        SELECT company_id FROM public.profiles
        WHERE id = auth.uid() AND company_id IS NOT NULL
    )
    AND NOT EXISTS (
        SELECT 1 FROM public.profiles x
        WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
);

-- ── Partner-dokumenter (HMS-lignende + kun bil-eier) ───────────────────────
ALTER TABLE public.partner_documents
    ADD COLUMN IF NOT EXISTS document_type TEXT NOT NULL DEFAULT 'annet',
    ADD COLUMN IF NOT EXISTS description TEXT,
    ADD COLUMN IF NOT EXISTS expires_at DATE,
    ADD COLUMN IF NOT EXISTS owner_visible BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS driver_visible BOOLEAN NOT NULL DEFAULT false;

-- ── Møter / audit med sporing ──────────────────────────────────────────────
ALTER TABLE public.partner_meetings
    ADD COLUMN IF NOT EXISTS meeting_type TEXT NOT NULL DEFAULT 'dirigert',
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'planlagt',
    ADD COLUMN IF NOT EXISTS sms_sent_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS sms_message TEXT,
    ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS audit_status_after TEXT,
    ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE;

UPDATE public.partner_meetings pm
SET company_id = p.company_id
FROM public.partners p
WHERE pm.partner_id = p.id AND pm.company_id IS NULL;
