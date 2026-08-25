-- Partner workforce (ansatte + stempling) — soft-delete / full audit, feature-flag per partner.

ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS workforce_enabled boolean NOT NULL DEFAULT false;

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS partner_workforce_enabled_all boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.partners.workforce_enabled IS
  'Når true (eller companies.partner_workforce_enabled_all): partner kan administrere ansatte og timer.';
COMMENT ON COLUMN public.companies.partner_workforce_enabled_all IS
  'Superadmin master-bryter: aktiverer workforce for alle partnere uten å slette data.';

ALTER TABLE public.partner_portal_accounts
  DROP CONSTRAINT IF EXISTS partner_portal_accounts_account_kind_check;

ALTER TABLE public.partner_portal_accounts
  ADD CONSTRAINT partner_portal_accounts_account_kind_check
  CHECK (account_kind IN ('owner', 'driver', 'staff'));

CREATE TABLE IF NOT EXISTS public.partner_staff (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id uuid NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  phone text,
  address text,
  postal_code text,
  city text,
  portal_account_id uuid REFERENCES public.partner_portal_accounts(id) ON DELETE SET NULL,
  profile_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  is_active boolean NOT NULL DEFAULT true,
  deactivated_at timestamptz,
  notes text,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_partner_staff_partner
  ON public.partner_staff (partner_id, is_active);
CREATE INDEX IF NOT EXISTS idx_partner_staff_profile
  ON public.partner_staff (profile_id)
  WHERE profile_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.partner_time_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id uuid NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  staff_id uuid NOT NULL REFERENCES public.partner_staff(id) ON DELETE RESTRICT,
  clock_in timestamptz NOT NULL,
  clock_out timestamptz,
  note text,
  source text NOT NULL DEFAULT 'mobile'
    CHECK (source IN ('mobile', 'manual', 'import', 'owner_edit', 'admin_edit')),
  is_deleted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT partner_time_entries_order CHECK (
    clock_out IS NULL OR clock_out >= clock_in
  )
);

CREATE INDEX IF NOT EXISTS idx_partner_time_entries_staff_day
  ON public.partner_time_entries (staff_id, clock_in DESC)
  WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS idx_partner_time_entries_partner
  ON public.partner_time_entries (partner_id, clock_in DESC);

CREATE TABLE IF NOT EXISTS public.partner_time_entry_audits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_id uuid NOT NULL REFERENCES public.partner_time_entries(id) ON DELETE CASCADE,
  partner_id uuid NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  action text NOT NULL
    CHECK (action IN ('create', 'update', 'soft_delete', 'restore', 'punch_in', 'punch_out')),
  changed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  changed_at timestamptz NOT NULL DEFAULT now(),
  before_json jsonb,
  after_json jsonb,
  reason text
);

CREATE INDEX IF NOT EXISTS idx_partner_time_audits_entry
  ON public.partner_time_entry_audits (entry_id, changed_at DESC);

CREATE INDEX IF NOT EXISTS idx_partner_time_audits_partner
  ON public.partner_time_entry_audits (partner_id, changed_at DESC);

CREATE OR REPLACE FUNCTION public.partner_workforce_is_enabled(p_partner_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT c.partner_workforce_enabled_all
       FROM public.companies c
       JOIN public.partners p ON p.company_id = c.id
      WHERE p.id = p_partner_id),
    false
  )
  OR COALESCE(
    (SELECT p.workforce_enabled FROM public.partners p WHERE p.id = p_partner_id),
    false
  );
$$;

CREATE OR REPLACE FUNCTION public._partner_time_entry_snapshot(e public.partner_time_entries)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'id', e.id,
    'staff_id', e.staff_id,
    'clock_in', e.clock_in,
    'clock_out', e.clock_out,
    'note', e.note,
    'source', e.source,
    'is_deleted', e.is_deleted
  );
$$;

CREATE OR REPLACE FUNCTION public.partner_time_entries_audit_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.partner_time_entry_audits (
      entry_id, partner_id, company_id, action, changed_by, before_json, after_json
    ) VALUES (
      NEW.id, NEW.partner_id, NEW.company_id,
      CASE WHEN NEW.source IN ('mobile') AND NEW.clock_out IS NULL THEN 'punch_in' ELSE 'create' END,
      NEW.created_by,
      NULL,
      public._partner_time_entry_snapshot(NEW)
    );
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    INSERT INTO public.partner_time_entry_audits (
      entry_id, partner_id, company_id, action, changed_by, before_json, after_json
    ) VALUES (
      NEW.id, NEW.partner_id, NEW.company_id,
      CASE
        WHEN NEW.is_deleted AND NOT OLD.is_deleted THEN 'soft_delete'
        WHEN NOT NEW.is_deleted AND OLD.is_deleted THEN 'restore'
        WHEN OLD.clock_out IS NULL AND NEW.clock_out IS NOT NULL THEN 'punch_out'
        ELSE 'update'
      END,
      NEW.updated_by,
      public._partner_time_entry_snapshot(OLD),
      public._partner_time_entry_snapshot(NEW)
    );
    RETURN NEW;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_partner_time_entries_audit ON public.partner_time_entries;
CREATE TRIGGER trg_partner_time_entries_audit
  AFTER INSERT OR UPDATE ON public.partner_time_entries
  FOR EACH ROW EXECUTE FUNCTION public.partner_time_entries_audit_trg();

CREATE OR REPLACE FUNCTION public.partner_time_entries_block_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'partner_time_entries kan ikke slettes hardt — bruk soft-delete (is_deleted)';
END;
$$;

DROP TRIGGER IF EXISTS trg_partner_time_entries_no_delete ON public.partner_time_entries;
CREATE TRIGGER trg_partner_time_entries_no_delete
  BEFORE DELETE ON public.partner_time_entries
  FOR EACH ROW EXECUTE FUNCTION public.partner_time_entries_block_delete();

CREATE OR REPLACE FUNCTION public.partner_workforce_punch()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_staff public.partner_staff%ROWTYPE;
  v_open public.partner_time_entries%ROWTYPE;
  v_new public.partner_time_entries%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_staff
  FROM public.partner_staff s
  WHERE s.profile_id = v_uid AND s.is_active = true
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ingen aktiv ansatt-profil for stempling';
  END IF;

  IF NOT public.partner_workforce_is_enabled(v_staff.partner_id) THEN
    RAISE EXCEPTION 'Stempling er ikke aktivert for denne bedriften';
  END IF;

  SELECT * INTO v_open
  FROM public.partner_time_entries e
  WHERE e.staff_id = v_staff.id
    AND e.is_deleted = false
    AND e.clock_out IS NULL
  ORDER BY e.clock_in DESC
  LIMIT 1;

  IF FOUND THEN
    UPDATE public.partner_time_entries
    SET clock_out = now(),
        updated_at = now(),
        updated_by = v_uid,
        source = 'mobile'
    WHERE id = v_open.id
    RETURNING * INTO v_new;
    RETURN jsonb_build_object(
      'action', 'punch_out',
      'entry', public._partner_time_entry_snapshot(v_new)
    );
  END IF;

  INSERT INTO public.partner_time_entries (
    partner_id, company_id, staff_id, clock_in, source, created_by, updated_by
  ) VALUES (
    v_staff.partner_id, v_staff.company_id, v_staff.id, now(), 'mobile', v_uid, v_uid
  )
  RETURNING * INTO v_new;

  RETURN jsonb_build_object(
    'action', 'punch_in',
    'entry', public._partner_time_entry_snapshot(v_new)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.partner_workforce_is_enabled(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.partner_workforce_punch() TO authenticated;

ALTER TABLE public.partner_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_time_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_time_entry_audits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS partner_staff_select ON public.partner_staff;
CREATE POLICY partner_staff_select ON public.partner_staff
  FOR SELECT TO authenticated
  USING (
    company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    OR profile_id = auth.uid()
    OR partner_id IN (
      SELECT partner_id FROM public.partner_portal_accounts
      WHERE profile_id = auth.uid() AND is_active AND account_kind = 'owner'
    )
  );

DROP POLICY IF EXISTS partner_staff_write ON public.partner_staff;
CREATE POLICY partner_staff_write ON public.partner_staff
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.company_id = partner_staff.company_id
        AND p.role IN ('admin', 'superadmin')
    )
    OR partner_id IN (
      SELECT partner_id FROM public.partner_portal_accounts
      WHERE profile_id = auth.uid() AND is_active AND account_kind = 'owner'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.company_id = partner_staff.company_id
        AND p.role IN ('admin', 'superadmin')
    )
    OR partner_id IN (
      SELECT partner_id FROM public.partner_portal_accounts
      WHERE profile_id = auth.uid() AND is_active AND account_kind = 'owner'
    )
  );

DROP POLICY IF EXISTS partner_time_entries_select ON public.partner_time_entries;
CREATE POLICY partner_time_entries_select ON public.partner_time_entries
  FOR SELECT TO authenticated
  USING (
    company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    OR staff_id IN (SELECT id FROM public.partner_staff WHERE profile_id = auth.uid())
    OR partner_id IN (
      SELECT partner_id FROM public.partner_portal_accounts
      WHERE profile_id = auth.uid() AND is_active AND account_kind = 'owner'
    )
  );

DROP POLICY IF EXISTS partner_time_entries_write ON public.partner_time_entries;
CREATE POLICY partner_time_entries_write ON public.partner_time_entries
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.company_id = partner_time_entries.company_id
        AND p.role IN ('admin', 'superadmin')
    )
    OR partner_id IN (
      SELECT partner_id FROM public.partner_portal_accounts
      WHERE profile_id = auth.uid() AND is_active AND account_kind = 'owner'
    )
    OR staff_id IN (SELECT id FROM public.partner_staff WHERE profile_id = auth.uid() AND is_active)
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.company_id = partner_time_entries.company_id
        AND p.role IN ('admin', 'superadmin')
    )
    OR partner_id IN (
      SELECT partner_id FROM public.partner_portal_accounts
      WHERE profile_id = auth.uid() AND is_active AND account_kind = 'owner'
    )
    OR staff_id IN (SELECT id FROM public.partner_staff WHERE profile_id = auth.uid() AND is_active)
  );

DROP POLICY IF EXISTS partner_time_audits_select ON public.partner_time_entry_audits;
CREATE POLICY partner_time_audits_select ON public.partner_time_entry_audits
  FOR SELECT TO authenticated
  USING (
    company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid())
    OR partner_id IN (
      SELECT partner_id FROM public.partner_portal_accounts
      WHERE profile_id = auth.uid() AND is_active AND account_kind = 'owner'
    )
  );

REVOKE INSERT, UPDATE, DELETE ON public.partner_time_entry_audits FROM authenticated;
GRANT SELECT ON public.partner_staff TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.partner_time_entries TO authenticated;
GRANT SELECT ON public.partner_time_entry_audits TO authenticated;
