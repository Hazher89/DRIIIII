-- Fravær/ferie: streng RLS, kvoter, organisasjonskart-kobling.
-- Sikrer at ansatt kun ser egne data, leder ser avdeling, admin ser alt.

-- ── Hjelpefunksjoner ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_company_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.get_user_role() IN ('admin'::public.user_role, 'superadmin'::public.user_role);
$$;

CREATE OR REPLACE FUNCTION public.is_department_leader_of(p_department_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p_department_id IS NOT NULL
    AND (
      EXISTS (
        SELECT 1
        FROM public.department_leaders dl
        WHERE dl.department_id = p_department_id
          AND dl.profile_id = auth.uid()
      )
      OR EXISTS (
        SELECT 1
        FROM public.departments d
        WHERE d.id = p_department_id
          AND d.leader_id = auth.uid()
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.profile_in_my_data_scope(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p_user_id = auth.uid()
    OR (
      public.is_company_admin()
      AND EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = p_user_id
          AND p.company_id = public.get_user_company_id()
      )
    )
    OR (
      public.get_user_role() = 'leder'::public.user_role
      AND EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = p_user_id
          AND p.company_id = public.get_user_company_id()
          AND p.department_id IS NOT DISTINCT FROM public.get_user_department_id()
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.absence_visible(p_absence public.absences)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.profile_in_my_data_scope(p_absence.user_id);
$$;

-- Sett avdeling fra ansattprofil ved innlegg (holder org-kart og fravær synkron).
CREATE OR REPLACE FUNCTION public.sync_absence_department_from_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _dept uuid;
BEGIN
  SELECT department_id INTO _dept
  FROM public.profiles
  WHERE id = NEW.user_id;

  NEW.department_id := _dept;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_absence_department ON public.absences;
CREATE TRIGGER trg_sync_absence_department
  BEFORE INSERT OR UPDATE OF user_id ON public.absences
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_absence_department_from_profile();

-- Auto-opprett feriekvote når ny ansatt legges til (organisasjonskart / import).
CREATE OR REPLACE FUNCTION public.trg_profiles_ensure_absence_quota()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.is_active IS DISTINCT FROM FALSE
     AND NEW.role IS DISTINCT FROM 'samarbeidspartner'::public.user_role
     AND NEW.company_id IS NOT NULL THEN
    PERFORM public.ensure_absence_quota(NEW.id, extract(year from now())::int);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_ensure_absence_quota ON public.profiles;
CREATE TRIGGER trg_profiles_ensure_absence_quota
  AFTER INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_profiles_ensure_absence_quota();

-- ── ensure_absence_quota (idempotent) ───────────────────────────────────────

CREATE OR REPLACE FUNCTION public.ensure_absence_quota(
  p_user_id uuid DEFAULT auth.uid(),
  p_year integer DEFAULT extract(year FROM now())::int
)
RETURNS public.absence_quotas
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _profile public.profiles%rowtype;
  _row public.absence_quotas%rowtype;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Mangler bruker-id';
  END IF;

  IF p_user_id IS DISTINCT FROM auth.uid()
     AND public.get_user_role() NOT IN ('admin'::public.user_role, 'superadmin'::public.user_role, 'leder'::public.user_role) THEN
    RAISE EXCEPTION 'Ikke tilgang til å opprette saldo for andre';
  END IF;

  SELECT * INTO _profile FROM public.profiles WHERE id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bruker ikke funnet';
  END IF;

  IF public.get_user_role() = 'leder'::public.user_role
     AND p_user_id IS DISTINCT FROM auth.uid() THEN
    IF _profile.department_id IS DISTINCT FROM public.get_user_department_id() THEN
      RAISE EXCEPTION 'Leder kan kun opprette saldo for egen avdeling';
    END IF;
  END IF;

  INSERT INTO public.absence_quotas (user_id, company_id, year, vacation_days_total)
  VALUES (p_user_id, _profile.company_id, p_year, 25)
  ON CONFLICT (user_id, year) DO NOTHING;

  SELECT * INTO _row FROM public.absence_quotas
  WHERE user_id = p_user_id AND year = p_year;

  RETURN _row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_absence_quota(uuid, integer) TO authenticated;

-- ── Deaktiver ansatt (organisasjonskart / admin) ────────────────────────────

CREATE OR REPLACE FUNCTION public.deactivate_employee_profile(p_profile_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _target public.profiles%rowtype;
  _role public.user_role;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  _role := public.get_user_role();

  SELECT * INTO _target FROM public.profiles WHERE id = p_profile_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ansatt ikke funnet';
  END IF;

  IF _target.company_id IS DISTINCT FROM public.get_user_company_id()
     AND _role IS DISTINCT FROM 'superadmin'::public.user_role THEN
    RAISE EXCEPTION 'Feil selskap';
  END IF;

  IF _target.role = 'superadmin'::public.user_role
     AND _role IS DISTINCT FROM 'superadmin'::public.user_role THEN
    RAISE EXCEPTION 'Kan ikke deaktivere superadmin';
  END IF;

  IF p_profile_id = auth.uid() THEN
    RAISE EXCEPTION 'Du kan ikke deaktivere deg selv';
  END IF;

  IF _role = 'leder'::public.user_role THEN
    IF _target.department_id IS DISTINCT FROM public.get_user_department_id() THEN
      RAISE EXCEPTION 'Leder kan kun deaktivere ansatte i egen avdeling';
    END IF;
  ELSIF _role NOT IN ('admin'::public.user_role, 'superadmin'::public.user_role) THEN
    RAISE EXCEPTION 'Mangler tilgang';
  END IF;

  UPDATE public.profiles
  SET is_active = false, updated_at = now()
  WHERE id = p_profile_id;

  UPDATE public.employee_login_accounts
  SET is_active = false, updated_at = now()
  WHERE profile_id = p_profile_id;

  DELETE FROM public.department_leaders WHERE profile_id = p_profile_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.deactivate_employee_profile(uuid) TO authenticated;

-- Admin kan også slette permanent (utvidet fra kun superadmin).
CREATE OR REPLACE FUNCTION public.admin_delete_user_hard(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  requester_id uuid := auth.uid();
  requester_role public.user_role;
  requester_company uuid;
  target_company uuid;
  target_role public.user_role;
BEGIN
  IF requester_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  requester_role := public.get_user_role();
  requester_company := public.get_user_company_id();

  IF requester_role NOT IN ('superadmin'::public.user_role, 'admin'::public.user_role) THEN
    RAISE EXCEPTION 'Kun admin/superadmin kan slette brukere permanent';
  END IF;

  IF requester_id = target_user_id THEN
    RAISE EXCEPTION 'Cannot delete yourself';
  END IF;

  SELECT p.company_id, p.role
  INTO target_company, target_role
  FROM public.profiles p
  WHERE p.id = target_user_id;

  IF target_company IS NULL THEN
    RAISE EXCEPTION 'Target user not found in profiles';
  END IF;

  IF requester_role IS DISTINCT FROM 'superadmin'::public.user_role
     AND target_company IS DISTINCT FROM requester_company THEN
    RAISE EXCEPTION 'Cannot delete user from another company';
  END IF;

  IF target_role = 'superadmin'::public.user_role
     AND requester_role IS DISTINCT FROM 'superadmin'::public.user_role THEN
    RAISE EXCEPTION 'Only superadmin can delete superadmin';
  END IF;

  DELETE FROM storage.objects WHERE owner = target_user_id;
  DELETE FROM auth.users WHERE id = target_user_id;
END;
$$;

-- ── ABSENCES: erstatt policies ──────────────────────────────────────────────

DROP POLICY IF EXISTS "Ansatte kan se eget fravær" ON public.absences;
DROP POLICY IF EXISTS "Ledere kan se fravær i sin avdeling" ON public.absences;
DROP POLICY IF EXISTS "Admin kan se alt fravær i selskapet" ON public.absences;
DROP POLICY IF EXISTS "Ansatte kan registrere eget fravær" ON public.absences;
DROP POLICY IF EXISTS "Ledere kan godkjenne fravær i sin avdeling" ON public.absences;
DROP POLICY IF EXISTS absences_insert_manager ON public.absences;
DROP POLICY IF EXISTS absences_select_scoped ON public.absences;
DROP POLICY IF EXISTS absences_insert_self ON public.absences;
DROP POLICY IF EXISTS absences_update_self_pending ON public.absences;
DROP POLICY IF EXISTS absences_update_manager ON public.absences;
DROP POLICY IF EXISTS absences_delete_scoped ON public.absences;

CREATE POLICY absences_select_scoped ON public.absences
  FOR SELECT TO authenticated
  USING (public.absence_visible(absences));

CREATE POLICY absences_insert_self ON public.absences
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND company_id = public.get_user_company_id()
  );

CREATE POLICY absences_insert_manager ON public.absences
  FOR INSERT TO authenticated
  WITH CHECK (
    company_id = public.get_user_company_id()
    AND user_id IS DISTINCT FROM auth.uid()
    AND public.profile_in_my_data_scope(user_id)
    AND (
      public.is_company_admin()
      OR (
        public.get_user_role() = 'leder'::public.user_role
        AND EXISTS (
          SELECT 1 FROM public.profiles emp
          WHERE emp.id = user_id
            AND emp.department_id IS NOT DISTINCT FROM public.get_user_department_id()
        )
      )
    )
  );

CREATE POLICY absences_update_self_pending ON public.absences
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() AND status = 'ventende'::public.absence_status)
  WITH CHECK (user_id = auth.uid());

CREATE POLICY absences_update_manager ON public.absences
  FOR UPDATE TO authenticated
  USING (
    public.absence_visible(absences)
    AND user_id IS DISTINCT FROM auth.uid()
    AND (
      public.is_company_admin()
      OR public.get_user_role() = 'leder'::public.user_role
    )
  )
  WITH CHECK (public.absence_visible(absences));

CREATE POLICY absences_delete_scoped ON public.absences
  FOR DELETE TO authenticated
  USING (
    (user_id = auth.uid() AND status = 'ventende'::public.absence_status)
    OR (
      public.is_company_admin()
      AND company_id = public.get_user_company_id()
    )
    OR (
      public.get_user_role() = 'leder'::public.user_role
      AND public.profile_in_my_data_scope(user_id)
      AND user_id IS DISTINCT FROM auth.uid()
    )
  );

-- ── ABSENCE QUOTAS ──────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Ansatte kan se egne kvoter" ON public.absence_quotas;
DROP POLICY IF EXISTS "Admin kan se alle kvoter i selskapet" ON public.absence_quotas;
DROP POLICY IF EXISTS "Ledere kan se kvoter i avdeling" ON public.absence_quotas;
DROP POLICY IF EXISTS absence_quotas_select_scoped ON public.absence_quotas;
DROP POLICY IF EXISTS absence_quotas_update_admin ON public.absence_quotas;
DROP POLICY IF EXISTS absence_quotas_update_leader_dept ON public.absence_quotas;
DROP POLICY IF EXISTS absence_quotas_insert_admin ON public.absence_quotas;

CREATE POLICY absence_quotas_select_scoped ON public.absence_quotas
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR (
      public.is_company_admin()
      AND company_id = public.get_user_company_id()
    )
    OR (
      public.get_user_role() = 'leder'::public.user_role
      AND company_id = public.get_user_company_id()
      AND user_id IN (
        SELECT id FROM public.profiles
        WHERE department_id IS NOT DISTINCT FROM public.get_user_department_id()
      )
    )
  );

CREATE POLICY absence_quotas_update_admin ON public.absence_quotas
  FOR UPDATE TO authenticated
  USING (
    public.is_company_admin()
    AND company_id = public.get_user_company_id()
  )
  WITH CHECK (company_id = public.get_user_company_id());

CREATE POLICY absence_quotas_update_leader_dept ON public.absence_quotas
  FOR UPDATE TO authenticated
  USING (
    public.get_user_role() = 'leder'::public.user_role
    AND company_id = public.get_user_company_id()
    AND user_id IN (
      SELECT id FROM public.profiles
      WHERE department_id IS NOT DISTINCT FROM public.get_user_department_id()
    )
    AND user_id IS DISTINCT FROM auth.uid()
  )
  WITH CHECK (
    company_id = public.get_user_company_id()
    AND user_id IS DISTINCT FROM auth.uid()
  );

CREATE POLICY absence_quotas_insert_admin ON public.absence_quotas
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_company_admin()
    AND company_id = public.get_user_company_id()
  );

-- ── TICKETS: ansatt kun egne ────────────────────────────────────────────────

DROP POLICY IF EXISTS "Ansatte kan se avvik i sin avdeling" ON public.tickets;
DROP POLICY IF EXISTS "Ansatte kan opprette avvik" ON public.tickets;
DROP POLICY IF EXISTS "Ledere kan oppdatere avvik i sin avdeling" ON public.tickets;
DROP POLICY IF EXISTS tickets_select_scoped ON public.tickets;
DROP POLICY IF EXISTS tickets_insert_company ON public.tickets;
DROP POLICY IF EXISTS tickets_update_scoped ON public.tickets;

CREATE POLICY tickets_select_scoped ON public.tickets
  FOR SELECT TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      public.is_company_admin()
      OR reported_by = auth.uid()
      OR assigned_to = auth.uid()
      OR (
        public.get_user_role() = 'leder'::public.user_role
        AND (
          department_id IS NOT DISTINCT FROM public.get_user_department_id()
          OR EXISTS (
            SELECT 1 FROM public.profiles rep
            WHERE rep.id = tickets.reported_by
              AND rep.department_id IS NOT DISTINCT FROM public.get_user_department_id()
          )
        )
      )
    )
  );

CREATE POLICY tickets_insert_company ON public.tickets
  FOR INSERT TO authenticated
  WITH CHECK (
    company_id = public.get_user_company_id()
    AND reported_by = auth.uid()
  );

CREATE POLICY tickets_update_scoped ON public.tickets
  FOR UPDATE TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      reported_by = auth.uid()
      OR assigned_to = auth.uid()
      OR public.is_department_leader_of(department_id)
      OR public.is_company_admin()
      OR (
        public.get_user_role() = 'leder'::public.user_role
        AND (
          department_id IS NOT DISTINCT FROM public.get_user_department_id()
          OR EXISTS (
            SELECT 1 FROM public.profiles rep
            WHERE rep.id = tickets.reported_by
              AND rep.department_id IS NOT DISTINCT FROM public.get_user_department_id()
          )
        )
      )
    )
  )
  WITH CHECK (company_id = public.get_user_company_id());

-- ── PROFILES: leder kan oppdatere avdeling (organisasjonskart) ──────────────

DROP POLICY IF EXISTS "Ledere kan oppdatere ansatte i avdeling" ON public.profiles;
DROP POLICY IF EXISTS profiles_update_leader_department ON public.profiles;
CREATE POLICY profiles_update_leader_department ON public.profiles
  FOR UPDATE TO authenticated
  USING (
    public.get_user_role() = 'leder'::public.user_role
    AND company_id = public.get_user_company_id()
    AND department_id IS NOT DISTINCT FROM public.get_user_department_id()
    AND id IS DISTINCT FROM auth.uid()
    AND role NOT IN ('admin'::public.user_role, 'superadmin'::public.user_role)
  )
  WITH CHECK (
    company_id = public.get_user_company_id()
    AND department_id IS NOT DISTINCT FROM public.get_user_department_id()
  );

DROP POLICY IF EXISTS "Ledere kan opprette ansatte i avdeling" ON public.profiles;
-- INSERT skjer via Edge Function + auth.users (employee_provision), ikke direkte.

-- ── Kvoteoppdatering ved godkjenning (INSERT + tilbakeføring) ───────────────

CREATE OR REPLACE FUNCTION public.update_absence_quota()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF new.status = 'godkjent' AND (
    tg_op = 'INSERT'
    OR old.status IS DISTINCT FROM 'godkjent'
  ) THEN
    IF new.type = 'egenmelding' THEN
      UPDATE public.absence_quotas
      SET egenmelding_days_used = egenmelding_days_used + new.total_days,
          egenmelding_periods_used = egenmelding_periods_used + 1
      WHERE user_id = new.user_id AND year = new.quota_year;
    ELSIF new.type = 'ferie' THEN
      UPDATE public.absence_quotas
      SET vacation_days_used = vacation_days_used + new.total_days
      WHERE user_id = new.user_id AND year = new.quota_year;
    ELSIF new.type = 'sykt_barn' THEN
      UPDATE public.absence_quotas
      SET sykt_barn_days_used = sykt_barn_days_used + new.total_days
      WHERE user_id = new.user_id AND year = new.quota_year;
    END IF;
  END IF;

  IF tg_op = 'UPDATE'
    AND old.status = 'godkjent'
    AND new.status IS DISTINCT FROM 'godkjent' THEN
    IF old.type = 'egenmelding' THEN
      UPDATE public.absence_quotas
      SET egenmelding_days_used = greatest(0, egenmelding_days_used - old.total_days),
          egenmelding_periods_used = greatest(0, egenmelding_periods_used - 1)
      WHERE user_id = old.user_id AND year = old.quota_year;
    ELSIF old.type = 'ferie' THEN
      UPDATE public.absence_quotas
      SET vacation_days_used = greatest(0, vacation_days_used - old.total_days)
      WHERE user_id = old.user_id AND year = old.quota_year;
    ELSIF old.type = 'sykt_barn' THEN
      UPDATE public.absence_quotas
      SET sykt_barn_days_used = greatest(0, sykt_barn_days_used - old.total_days)
      WHERE user_id = old.user_id AND year = old.quota_year;
    END IF;
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS update_quota_on_approval ON public.absences;
CREATE TRIGGER update_quota_on_approval
  AFTER INSERT OR UPDATE ON public.absences
  FOR EACH ROW
  EXECUTE FUNCTION public.update_absence_quota();
