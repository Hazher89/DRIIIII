-- Global SMS-sikkerhet + hard sletting av samarbeidspartner.

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
      JOIN public.partners p ON p.id = ppa.partner_id
      JOIN normalized n ON true
      WHERE p.company_id = p_company_id
        AND p.is_active = true
        AND ppa.is_active = true
        AND public.normalize_phone_no(ppa.phone) = n.phone
    );
$$;

GRANT EXECUTE ON FUNCTION public.is_active_sms_phone_for_company(UUID, TEXT) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.purge_pending_sms_for_phone(
  p_company_id UUID,
  p_phone TEXT
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone TEXT;
  v_count INT := 0;
BEGIN
  v_phone := public.normalize_phone_no(p_phone);
  IF p_company_id IS NULL OR v_phone IS NULL THEN
    RETURN 0;
  END IF;
  DELETE FROM public.sms_outbox
  WHERE company_id = p_company_id
    AND to_phone = v_phone
    AND sent_at IS NULL;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.purge_pending_sms_for_phone(UUID, TEXT) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.trg_profiles_sms_phone_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF (coalesce(OLD.phone, '') <> coalesce(NEW.phone, ''))
       OR (coalesce(OLD.is_active, true) <> coalesce(NEW.is_active, true)) THEN
      PERFORM public.purge_pending_sms_for_phone(NEW.company_id, OLD.phone);
      IF NEW.is_active = false THEN
        PERFORM public.purge_pending_sms_for_phone(NEW.company_id, NEW.phone);
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_sms_phone_cleanup ON public.profiles;
CREATE TRIGGER profiles_sms_phone_cleanup
  AFTER UPDATE OF phone, is_active ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_profiles_sms_phone_cleanup();

CREATE OR REPLACE FUNCTION public.trg_partners_sms_phone_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF (coalesce(OLD.phone, '') <> coalesce(NEW.phone, ''))
       OR (coalesce(OLD.is_active, true) <> coalesce(NEW.is_active, true)) THEN
      PERFORM public.purge_pending_sms_for_phone(NEW.company_id, OLD.phone);
      IF NEW.is_active = false THEN
        PERFORM public.purge_pending_sms_for_phone(NEW.company_id, NEW.phone);
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS partners_sms_phone_cleanup ON public.partners;
CREATE TRIGGER partners_sms_phone_cleanup
  AFTER UPDATE OF phone, is_active ON public.partners
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_partners_sms_phone_cleanup();

CREATE OR REPLACE FUNCTION public.trg_partner_portal_accounts_sms_phone_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF (coalesce(OLD.phone, '') <> coalesce(NEW.phone, ''))
       OR (coalesce(OLD.is_active, true) <> coalesce(NEW.is_active, true)) THEN
      PERFORM public.purge_pending_sms_for_phone(NEW.company_id, OLD.phone);
      IF NEW.is_active = false THEN
        PERFORM public.purge_pending_sms_for_phone(NEW.company_id, NEW.phone);
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS partner_portal_accounts_sms_phone_cleanup ON public.partner_portal_accounts;
CREATE TRIGGER partner_portal_accounts_sms_phone_cleanup
  AFTER UPDATE OF phone, is_active ON public.partner_portal_accounts
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_partner_portal_accounts_sms_phone_cleanup();

CREATE OR REPLACE FUNCTION public.queue_sms(
  p_company_id UUID,
  p_to_phone TEXT,
  p_message TEXT,
  p_category TEXT DEFAULT NULL,
  p_reference_type TEXT DEFAULT NULL,
  p_reference_id UUID DEFAULT NULL,
  p_to_user_id UUID DEFAULT NULL,
  p_triggered_by_user_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized TEXT;
  new_id UUID;
BEGIN
  normalized := public.normalize_phone_no(p_to_phone);
  IF normalized IS NULL THEN
    RETURN NULL;
  END IF;
  IF p_message IS NULL OR length(trim(p_message)) = 0 THEN
    RETURN NULL;
  END IF;
  IF NOT public.is_active_sms_phone_for_company(p_company_id, normalized) THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.sms_outbox (
    company_id, to_phone, message, category, reference_type, reference_id,
    to_user_id, triggered_by_user_id
  ) VALUES (
    p_company_id,
    normalized,
    left(trim(p_message), 1071),
    p_category,
    p_reference_type,
    p_reference_id,
    p_to_user_id,
    COALESCE(p_triggered_by_user_id, auth.uid())
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.queue_sms(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.queue_sms(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID, UUID) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.hard_delete_partner_company(
  p_partner_id UUID,
  p_confirm BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_user_company_id UUID;
  v_settings JSONB;
  v_role TEXT;
  v_partner_user_id UUID;
  v_vehicle_ids UUID[] := ARRAY[]::UUID[];
  v_doc_paths TEXT[] := ARRAY[]::TEXT[];
  v_route_paths TEXT[] := ARRAY[]::TEXT[];
  v_sap_paths TEXT[] := ARRAY[]::TEXT[];
  v_deleted_profiles INT := 0;
  v_deleted_routes INT := 0;
  v_deleted_vehicles INT := 0;
  v_deleted_docs INT := 0;
BEGIN
  IF coalesce(p_confirm, false) = false THEN
    RAISE EXCEPTION 'Bekreftelse mangler for permanent sletting';
  END IF;

  SELECT p.company_id INTO v_company_id
  FROM public.partners p
  WHERE p.id = p_partner_id;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Samarbeidspartner finnes ikke';
  END IF;

  SELECT pr.company_id, pr.access_settings, pr.role::text, pr.partner_id
  INTO v_user_company_id, v_settings, v_role, v_partner_user_id
  FROM public.profiles pr
  WHERE pr.id = auth.uid();

  IF v_user_company_id IS NULL OR v_user_company_id <> v_company_id THEN
    RAISE EXCEPTION 'Ingen tilgang til å slette denne samarbeidspartneren';
  END IF;

  IF v_partner_user_id IS NOT NULL THEN
    RAISE EXCEPTION 'Portalbrukere kan ikke slette samarbeidspartner';
  END IF;

  IF v_role <> 'superadmin'
     AND coalesce((v_settings ->> 'partners_admin')::boolean, false) = false
     AND coalesce((v_settings ->> 'partners_delete')::boolean, false) = false THEN
    RAISE EXCEPTION 'Mangler tilgang: partners_delete / partners_admin';
  END IF;

  SELECT array_agg(pv.id) INTO v_vehicle_ids
  FROM public.partner_vehicles pv
  WHERE pv.partner_id = p_partner_id;
  v_vehicle_ids := coalesce(v_vehicle_ids, ARRAY[]::UUID[]);

  SELECT array_agg(pd.storage_path) INTO v_doc_paths
  FROM public.partner_documents pd
  WHERE pd.partner_id = p_partner_id
    AND pd.storage_path IS NOT NULL
    AND length(trim(pd.storage_path)) > 0;
  v_doc_paths := coalesce(v_doc_paths, ARRAY[]::TEXT[]);

  SELECT array_agg(prs.pdf_storage_path) INTO v_route_paths
  FROM public.partner_route_shares prs
  WHERE prs.partner_id = p_partner_id
    AND prs.pdf_storage_path IS NOT NULL
    AND length(trim(prs.pdf_storage_path)) > 0;
  v_route_paths := coalesce(v_route_paths, ARRAY[]::TEXT[]);

  SELECT array_agg(sri.pdf_storage_path) INTO v_sap_paths
  FROM public.sap_route_inbox sri
  JOIN public.partner_route_shares prs ON prs.id = sri.imported_route_share_id
  WHERE prs.partner_id = p_partner_id
    AND sri.pdf_storage_path IS NOT NULL
    AND length(trim(sri.pdf_storage_path)) > 0;
  v_sap_paths := coalesce(v_sap_paths, ARRAY[]::TEXT[]);

  UPDATE public.profiles
  SET
    partner_id = NULL,
    partner_vehicle_id = NULL,
    phone = NULL,
    phone_normalized = NULL,
    is_active = false,
    updated_at = now()
  WHERE partner_id = p_partner_id;
  GET DIAGNOSTICS v_deleted_profiles = ROW_COUNT;

  IF array_length(v_vehicle_ids, 1) IS NOT NULL THEN
    UPDATE public.profiles
    SET
      partner_vehicle_id = NULL,
      phone = NULL,
      phone_normalized = NULL,
      updated_at = now()
    WHERE partner_vehicle_id = ANY (v_vehicle_ids);

    DELETE FROM public.partner_vehicle_fleet_snapshots WHERE partner_vehicle_id = ANY (v_vehicle_ids);
    DELETE FROM public.lm_gps_positions WHERE partner_vehicle_id = ANY (v_vehicle_ids);
    DELETE FROM public.lm_route_stops
    WHERE route_id IN (
      SELECT id FROM public.lm_routes WHERE partner_vehicle_id = ANY (v_vehicle_ids)
    );
    DELETE FROM public.lm_route_custom_field_values
    WHERE route_id IN (
      SELECT id FROM public.lm_routes WHERE partner_vehicle_id = ANY (v_vehicle_ids)
    );
    DELETE FROM public.lm_routes WHERE partner_vehicle_id = ANY (v_vehicle_ids);
  END IF;

  DELETE FROM public.lm_route_stops
  WHERE route_id IN (
    SELECT id FROM public.lm_routes WHERE partner_id = p_partner_id
  );
  DELETE FROM public.lm_route_custom_field_values
  WHERE route_id IN (
    SELECT id FROM public.lm_routes WHERE partner_id = p_partner_id
  );
  DELETE FROM public.lm_routes WHERE partner_id = p_partner_id;

  DELETE FROM public.vehicle_rentals
  WHERE lender_partner_id = p_partner_id OR borrower_partner_id = p_partner_id;

  DELETE FROM public.partner_portal_accounts WHERE partner_id = p_partner_id;
  DELETE FROM public.partner_vehicle_inspections WHERE partner_id = p_partner_id;
  DELETE FROM public.partner_transport_licenses WHERE partner_id = p_partner_id;
  DELETE FROM public.partner_fri_requests WHERE partner_id = p_partner_id;
  DELETE FROM public.partner_meetings WHERE partner_id = p_partner_id;

  DELETE FROM public.sap_route_inbox
  WHERE imported_route_share_id IN (
    SELECT id FROM public.partner_route_shares WHERE partner_id = p_partner_id
  );

  DELETE FROM public.partner_documents WHERE partner_id = p_partner_id;
  GET DIAGNOSTICS v_deleted_docs = ROW_COUNT;

  DELETE FROM public.partner_route_shares WHERE partner_id = p_partner_id;
  GET DIAGNOSTICS v_deleted_routes = ROW_COUNT;

  DELETE FROM public.partner_vehicles WHERE partner_id = p_partner_id;
  GET DIAGNOSTICS v_deleted_vehicles = ROW_COUNT;

  DELETE FROM public.partners WHERE id = p_partner_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Samarbeidspartner ble ikke slettet';
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'deleted_profiles', v_deleted_profiles,
    'deleted_routes', v_deleted_routes,
    'deleted_vehicles', v_deleted_vehicles,
    'deleted_documents', v_deleted_docs,
    'storage_paths', to_jsonb(coalesce(v_doc_paths, ARRAY[]::TEXT[])) || to_jsonb(coalesce(v_route_paths, ARRAY[]::TEXT[])) || to_jsonb(coalesce(v_sap_paths, ARRAY[]::TEXT[]))
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.hard_delete_partner_company(UUID, BOOLEAN) TO authenticated, service_role;
