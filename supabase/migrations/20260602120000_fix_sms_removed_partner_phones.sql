-- Stopp rute-SMS til telefonnummer som er fjernet fra MAVI/sjåfør-portal.
-- Rotårsak: inaktiv portal deaktiverte ikke profil — profiles.is_active + phone matchet fortsatt i queue_sms.

-- ── Felles opprydding ved fjernet portal/telefon ─────────────────────────────
CREATE OR REPLACE FUNCTION public.revoke_partner_sms_phone(
  p_company_id UUID,
  p_phone TEXT,
  p_profile_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone TEXT;
BEGIN
  v_phone := public.normalize_phone_no(p_phone);
  IF p_company_id IS NULL OR v_phone IS NULL THEN
    RETURN;
  END IF;

  PERFORM public.purge_pending_sms_for_phone(p_company_id, v_phone);

  IF p_profile_id IS NOT NULL THEN
    UPDATE public.profiles
    SET
      is_active = false,
      phone = NULL,
      phone_normalized = NULL,
      updated_at = now()
    WHERE id = p_profile_id
      AND company_id = p_company_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.revoke_partner_sms_phone(UUID, TEXT, UUID) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.deactivate_partner_portal_account(
  p_portal_account_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.partner_portal_accounts%ROWTYPE;
BEGIN
  SELECT * INTO v_row
  FROM public.partner_portal_accounts
  WHERE id = p_portal_account_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  UPDATE public.partner_portal_accounts
  SET
    is_active = false,
    phone = NULL
  WHERE id = p_portal_account_id;

  IF v_row.partner_vehicle_id IS NOT NULL THEN
    UPDATE public.partner_vehicles
    SET phone = NULL, updated_at = now()
    WHERE id = v_row.partner_vehicle_id;
  END IF;

  PERFORM public.revoke_partner_sms_phone(
    v_row.company_id,
    v_row.phone,
    v_row.profile_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.deactivate_partner_portal_account(UUID) TO authenticated, service_role;

-- ── Kun aktive, gyldige kilder får SMS ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_active_sms_phone_for_company(
  p_company_id UUID,
  p_phone TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH normalized AS (
    SELECT public.normalize_phone_no(p_phone) AS phone
  )
  SELECT
    EXISTS (
      SELECT 1
      FROM public.profiles pr, normalized n
      WHERE pr.company_id = p_company_id
        AND pr.is_active = true
        AND pr.partner_id IS NULL
        AND coalesce(pr.phone_normalized, public.normalize_phone_no(pr.phone)) = n.phone
    )
    OR EXISTS (
      SELECT 1
      FROM public.partners p, normalized n
      WHERE p.company_id = p_company_id
        AND p.is_active = true
        AND public.normalize_phone_no(p.phone) = n.phone
    )
    OR EXISTS (
      SELECT 1
      FROM public.partner_portal_accounts ppa
      JOIN public.partners p ON p.id = ppa.partner_id AND p.is_active = true
      JOIN normalized n ON true
      LEFT JOIN public.partner_vehicles pv ON pv.id = ppa.partner_vehicle_id
      WHERE p.company_id = p_company_id
        AND ppa.is_active = true
        AND ppa.phone IS NOT NULL
        AND public.normalize_phone_no(ppa.phone) = n.phone
        AND (
          coalesce(ppa.account_kind, case when ppa.partner_vehicle_id is null then 'owner' else 'driver' end) = 'owner'
          OR (pv.id IS NOT NULL AND coalesce(pv.is_active, true) = true)
        )
    )
    OR EXISTS (
      SELECT 1
      FROM public.profiles pr
      JOIN public.partner_portal_accounts ppa ON ppa.profile_id = pr.id
      JOIN public.partners p ON p.id = ppa.partner_id AND p.is_active = true
      JOIN normalized n ON true
      LEFT JOIN public.partner_vehicles pv ON pv.id = ppa.partner_vehicle_id
      WHERE pr.company_id = p_company_id
        AND pr.is_active = true
        AND coalesce(pr.is_approved, false) = true
        AND coalesce(pr.phone_normalized, public.normalize_phone_no(pr.phone)) = n.phone
        AND ppa.is_active = true
        AND ppa.phone IS NOT NULL
        AND public.normalize_phone_no(ppa.phone) = n.phone
        AND (
          coalesce(ppa.account_kind, case when ppa.partner_vehicle_id is null then 'owner' else 'driver' end) = 'owner'
          OR (pv.id IS NOT NULL AND coalesce(pv.is_active, true) = true)
        )
    );
$$;

-- ── Triggere: opprydding ved endring/sletting ────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_partner_portal_accounts_sms_phone_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_phone TEXT;
  v_profile_id UUID;
BEGIN
  v_company_id := coalesce(NEW.company_id, OLD.company_id);
  v_phone := coalesce(OLD.phone, NEW.phone);
  v_profile_id := coalesce(OLD.profile_id, NEW.profile_id);

  IF TG_OP = 'DELETE' THEN
    PERFORM public.revoke_partner_sms_phone(v_company_id, OLD.phone, OLD.profile_id);
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF coalesce(OLD.phone, '') <> coalesce(NEW.phone, '')
       OR coalesce(OLD.is_active, true) <> coalesce(NEW.is_active, true) THEN
      PERFORM public.purge_pending_sms_for_phone(v_company_id, OLD.phone);
      IF NEW.is_active = false OR NEW.phone IS NULL THEN
        PERFORM public.revoke_partner_sms_phone(v_company_id, OLD.phone, OLD.profile_id);
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS partner_portal_accounts_sms_phone_cleanup ON public.partner_portal_accounts;
CREATE TRIGGER partner_portal_accounts_sms_phone_cleanup
  AFTER UPDATE OF phone, is_active OR DELETE ON public.partner_portal_accounts
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_partner_portal_accounts_sms_phone_cleanup();

CREATE OR REPLACE FUNCTION public.trg_partner_vehicles_sms_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_acc RECORD;
BEGIN
  IF TG_OP = 'DELETE' THEN
    FOR v_acc IN
      SELECT ppa.id
      FROM public.partner_portal_accounts ppa
      WHERE ppa.partner_vehicle_id = OLD.id
        AND coalesce(ppa.account_kind, 'driver') = 'driver'
    LOOP
      PERFORM public.deactivate_partner_portal_account(v_acc.id);
    END LOOP;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' AND coalesce(OLD.is_active, true) <> coalesce(NEW.is_active, true) AND NEW.is_active = false THEN
    FOR v_acc IN
      SELECT ppa.id
      FROM public.partner_portal_accounts ppa
      WHERE ppa.partner_vehicle_id = NEW.id
        AND ppa.is_active = true
        AND coalesce(ppa.account_kind, 'driver') = 'driver'
    LOOP
      PERFORM public.deactivate_partner_portal_account(v_acc.id);
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS partner_vehicles_sms_cleanup ON public.partner_vehicles;
CREATE TRIGGER partner_vehicles_sms_cleanup
  AFTER DELETE OR UPDATE OF is_active ON public.partner_vehicles
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_partner_vehicles_sms_cleanup();

-- Engangsopprydding: inaktive porter med telefon, profiler uten aktiv portal
UPDATE public.partner_portal_accounts
SET phone = NULL
WHERE is_active = false AND phone IS NOT NULL;

UPDATE public.partner_portal_accounts ppa
SET is_active = false, phone = NULL
WHERE ppa.is_active = true
  AND ppa.partner_vehicle_id IS NOT NULL
  AND coalesce(ppa.account_kind, 'driver') = 'driver'
  AND NOT EXISTS (
    SELECT 1 FROM public.partner_vehicles pv
    WHERE pv.id = ppa.partner_vehicle_id AND coalesce(pv.is_active, true) = true
  );

UPDATE public.profiles pr
SET
  is_active = false,
  phone = NULL,
  phone_normalized = NULL,
  updated_at = now()
WHERE pr.partner_id IS NOT NULL
  AND pr.partner_vehicle_id IS NOT NULL
  AND pr.is_active = true
  AND NOT EXISTS (
    SELECT 1
    FROM public.partner_portal_accounts ppa
    WHERE ppa.profile_id = pr.id
      AND ppa.is_active = true
      AND ppa.phone IS NOT NULL
      AND public.normalize_phone_no(ppa.phone) = coalesce(pr.phone_normalized, public.normalize_phone_no(pr.phone))
  );

DELETE FROM public.sms_outbox o
WHERE o.sent_at IS NULL
  AND o.category IN ('partner_route', 'partner_route_owner')
  AND NOT public.is_active_sms_phone_for_company(o.company_id, o.to_phone);
