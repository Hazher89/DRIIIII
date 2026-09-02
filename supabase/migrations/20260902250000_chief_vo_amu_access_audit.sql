-- Utvidede lovroller + revisjonslogg for tilgangs-/vervendringer.
-- Hovedverneombud (AML § 6-1) og AMU-medlem (AML kap. 7).

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_chief_safety_representative boolean NOT NULL DEFAULT false;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_amu_member boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.profiles.is_chief_safety_representative IS
  'Hovedverneombud — koordinerer vernetjenesten (AML § 6-1).';

COMMENT ON COLUMN public.profiles.is_amu_member IS
  'Medlem av arbeidsmiljøutvalg (AML kap. 7).';

CREATE INDEX IF NOT EXISTS profiles_chief_safety_rep_idx
  ON public.profiles (company_id)
  WHERE is_chief_safety_representative = true AND is_active = true;

CREATE INDEX IF NOT EXISTS profiles_amu_member_idx
  ON public.profiles (company_id)
  WHERE is_amu_member = true AND is_active = true;

-- Revisjon når ledelsen endrer verv / tilganger.
CREATE TABLE IF NOT EXISTS public.access_change_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  actor_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  target_profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  action text NOT NULL,
  summary text NOT NULL,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_access_change_audit_company
  ON public.access_change_audit (company_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_access_change_audit_target
  ON public.access_change_audit (target_profile_id, created_at DESC);

ALTER TABLE public.access_change_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS access_change_audit_select ON public.access_change_audit;
CREATE POLICY access_change_audit_select ON public.access_change_audit
  FOR SELECT TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      public.is_mavi_superadmin()
      OR public.is_company_admin()
      OR actor_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS access_change_audit_insert ON public.access_change_audit;
CREATE POLICY access_change_audit_insert ON public.access_change_audit
  FOR INSERT TO authenticated
  WITH CHECK (
    company_id = public.get_user_company_id()
    AND actor_id = auth.uid()
  );

COMMENT ON TABLE public.access_change_audit IS
  'Revisjonslogg for verv (verneombud/tillitsvalgt/AMU) og manuelle tilgangsendringer.';

-- Tillat service/trigger-lignende læring: assistent_memory kan også skrives
-- med visibility department:* uten ekstra sjekk (appen filtrerer ved lesing).
-- (Ingen schema-endring nødvendig — eksisterende INSERT-policy holder.)
