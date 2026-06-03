-- Deaktiver / aktiver samarbeidspartner (bedrift) med alle kjøretøy, portaler og SMS.

CREATE OR REPLACE FUNCTION public._partner_lifecycle_can_manage(p_partner_id UUID)
RETURNS UUID
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
BEGIN
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
    RAISE EXCEPTION 'Ingen tilgang til denne samarbeidspartneren';
  END IF;

  IF v_partner_user_id IS NOT NULL THEN
    RAISE EXCEPTION 'Portalbrukere kan ikke endre bedriftsstatus';
  END IF;

  IF v_role <> 'superadmin'
     AND coalesce((v_settings ->> 'partners_admin')::boolean, false) = false
     AND coalesce((v_settings ->> 'partners_delete')::boolean, false) = false THEN
    RAISE EXCEPTION 'Mangler tilgang: partners_admin / partners_delete';
  END IF;

  RETURN v_company_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.deactivate_partner_company(p_partner_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_vehicle_ids UUID[] := ARRAY[]::UUID[];
  v_portal RECORD;
  v_phones TEXT[] := ARRAY[]::TEXT[];
  v_phone TEXT;
  v_portals INT := 0;
  v_vehicles INT := 0;
  v_profiles INT := 0;
BEGIN
  v_company_id := public._partner_lifecycle_can_manage(p_partner_id);

  SELECT array_agg(pv.id) INTO v_vehicle_ids
  FROM public.partner_vehicles pv
  WHERE pv.partner_id = p_partner_id;
  v_vehicle_ids := coalesce(v_vehicle_ids, ARRAY[]::UUID[]);

  SELECT array_agg(DISTINCT ph) INTO v_phones
  FROM (
    SELECT public.normalize_phone_no(p.phone) AS ph
    FROM public.partners p
    WHERE p.id = p_partner_id
    UNION ALL
    SELECT public.normalize_phone_no(pv.phone)
    FROM public.partner_vehicles pv
    WHERE pv.partner_id = p_partner_id
    UNION ALL
    SELECT public.normalize_phone_no(ppa.phone)
    FROM public.partner_portal_accounts ppa
    WHERE ppa.partner_id = p_partner_id
  ) s
  WHERE ph IS NOT NULL;
  v_phones := coalesce(v_phones, ARRAY[]::TEXT[]);

  FOREACH v_phone IN ARRAY v_phones LOOP
    PERFORM public.purge_pending_sms_for_phone(v_company_id, v_phone);
  END LOOP;

  FOR v_portal IN
    SELECT id FROM public.partner_portal_accounts WHERE partner_id = p_partner_id
  LOOP
    PERFORM public.deactivate_partner_portal_account(v_portal.id);
    v_portals := v_portals + 1;
  END LOOP;

  UPDATE public.partner_vehicles
  SET is_active = false, updated_at = now()
  WHERE partner_id = p_partner_id;
  GET DIAGNOSTICS v_vehicles = ROW_COUNT;

  UPDATE public.profiles
  SET is_active = false, updated_at = now()
  WHERE partner_id = p_partner_id
     OR partner_vehicle_id = ANY (v_vehicle_ids);
  GET DIAGNOSTICS v_profiles = ROW_COUNT;

  UPDATE public.partners
  SET is_active = false, updated_at = now()
  WHERE id = p_partner_id;

  RETURN jsonb_build_object(
    'ok', true,
    'partner_id', p_partner_id,
    'deactivated_vehicles', v_vehicles,
    'deactivated_portals', v_portals,
    'deactivated_profiles', v_profiles
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.activate_partner_company(p_partner_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_vehicle_ids UUID[] := ARRAY[]::UUID[];
  v_vehicles INT := 0;
  v_portals INT := 0;
  v_profiles INT := 0;
BEGIN
  v_company_id := public._partner_lifecycle_can_manage(p_partner_id);

  SELECT array_agg(pv.id) INTO v_vehicle_ids
  FROM public.partner_vehicles pv
  WHERE pv.partner_id = p_partner_id;
  v_vehicle_ids := coalesce(v_vehicle_ids, ARRAY[]::UUID[]);

  UPDATE public.partners
  SET is_active = true, updated_at = now()
  WHERE id = p_partner_id;

  UPDATE public.partner_vehicles
  SET is_active = true, updated_at = now()
  WHERE partner_id = p_partner_id;
  GET DIAGNOSTICS v_vehicles = ROW_COUNT;

  UPDATE public.partner_portal_accounts
  SET is_active = true, updated_at = now()
  WHERE partner_id = p_partner_id;
  GET DIAGNOSTICS v_portals = ROW_COUNT;

  UPDATE public.profiles pr
  SET
    is_active = true,
    is_approved = true,
    updated_at = now()
  WHERE pr.company_id = v_company_id
    AND (
      pr.partner_id = p_partner_id
      OR pr.partner_vehicle_id = ANY (v_vehicle_ids)
      OR pr.id IN (
        SELECT ppa.profile_id FROM public.partner_portal_accounts ppa
        WHERE ppa.partner_id = p_partner_id AND ppa.profile_id IS NOT NULL
      )
    );
  GET DIAGNOSTICS v_profiles = ROW_COUNT;

  RETURN jsonb_build_object(
    'ok', true,
    'partner_id', p_partner_id,
    'activated_vehicles', v_vehicles,
    'activated_portals', v_portals,
    'activated_profiles', v_profiles
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.deactivate_partner_company(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.activate_partner_company(UUID) TO authenticated, service_role;
