-- Deaktiver ansatt + hard slett (med bypass av time-entry no-delete trigger).

CREATE OR REPLACE FUNCTION public.partner_time_entries_block_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('app.partner_workforce_hard_delete', true) = 'on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'partner_time_entries kan ikke slettes hardt — bruk soft-delete (is_deleted)';
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_staff_can_manage(p_partner_id uuid, p_company_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.company_id = p_company_id
        AND p.role IN ('admin', 'superadmin')
    )
    OR EXISTS (
      SELECT 1 FROM public.partner_portal_accounts ppa
      WHERE ppa.profile_id = auth.uid()
        AND ppa.partner_id = p_partner_id
        AND ppa.is_active
        AND ppa.account_kind = 'owner'
    );
$$;

CREATE OR REPLACE FUNCTION public.partner_staff_set_active(
  p_staff_id uuid,
  p_active boolean
)
RETURNS public.partner_staff
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.partner_staff%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_staff FROM public.partner_staff WHERE id = p_staff_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ansatt ikke funnet';
  END IF;

  IF NOT public.partner_staff_can_manage(v_staff.partner_id, v_staff.company_id) THEN
    RAISE EXCEPTION 'Mangler tilgang til å endre ansatt';
  END IF;

  UPDATE public.partner_staff
  SET
    is_active = p_active,
    deactivated_at = CASE WHEN p_active THEN NULL ELSE now() END,
    updated_at = now()
  WHERE id = p_staff_id
  RETURNING * INTO v_staff;

  IF v_staff.portal_account_id IS NOT NULL THEN
    UPDATE public.partner_portal_accounts
    SET is_active = p_active, updated_at = now()
    WHERE id = v_staff.portal_account_id;
  END IF;

  RETURN v_staff;
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_staff_hard_delete(p_staff_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.partner_staff%ROWTYPE;
  v_entries int := 0;
  v_audits int := 0;
  v_portal uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_staff FROM public.partner_staff WHERE id = p_staff_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ansatt ikke funnet';
  END IF;

  IF NOT public.partner_staff_can_manage(v_staff.partner_id, v_staff.company_id) THEN
    RAISE EXCEPTION 'Mangler tilgang til å slette ansatt';
  END IF;

  v_portal := v_staff.portal_account_id;

  -- Tillat hard delete av timer for denne operasjonen (lokalt til transaksjonen).
  PERFORM set_config('app.partner_workforce_hard_delete', 'on', true);

  DELETE FROM public.partner_time_entry_audits
  WHERE entry_id IN (
    SELECT id FROM public.partner_time_entries WHERE staff_id = p_staff_id
  );
  GET DIAGNOSTICS v_audits = ROW_COUNT;

  DELETE FROM public.partner_time_entries WHERE staff_id = p_staff_id;
  GET DIAGNOSTICS v_entries = ROW_COUNT;

  -- Koble fra portal før slett (behold portal-rad, men steng innlogging).
  UPDATE public.partner_staff
  SET portal_account_id = NULL, profile_id = NULL, updated_at = now()
  WHERE id = p_staff_id;

  IF v_portal IS NOT NULL THEN
    UPDATE public.partner_portal_accounts
    SET is_active = false, updated_at = now()
    WHERE id = v_portal;
  END IF;

  DELETE FROM public.partner_staff WHERE id = p_staff_id;

  RETURN jsonb_build_object(
    'staff_id', p_staff_id,
    'deleted_entries', v_entries,
    'deleted_audits', v_audits,
    'portal_removed', v_portal IS NOT NULL
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.partner_staff_can_manage(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.partner_staff_set_active(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.partner_staff_hard_delete(uuid) TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.partner_staff TO authenticated;
