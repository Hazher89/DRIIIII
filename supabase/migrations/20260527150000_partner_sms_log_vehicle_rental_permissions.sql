-- Partner SMS-logg (ambiguous id), aktive mottakere, bilutleie MAVI-låntaker + godkjenningstilgang.

-- ── Felles: kun aktive bileiere får SMS ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.partner_owner_sms_phones(p_partner_id UUID)
RETURNS TABLE(phone TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT public.normalize_phone_no(src.phone)
  FROM (
    SELECT p.phone
    FROM public.partners p
    WHERE p.id = p_partner_id AND p.is_active = true AND p.phone IS NOT NULL
    UNION ALL
    SELECT ppa.phone
    FROM public.partner_portal_accounts ppa
    JOIN public.partners p ON p.id = ppa.partner_id AND p.is_active = true
    WHERE ppa.partner_id = p_partner_id
      AND ppa.is_active = true
      AND coalesce(ppa.account_kind, case when ppa.partner_vehicle_id is null then 'owner' else 'driver' end) = 'owner'
      AND ppa.phone IS NOT NULL
    UNION ALL
    SELECT pr.phone
    FROM public.partner_portal_accounts ppa
    JOIN public.partners p ON p.id = ppa.partner_id AND p.is_active = true
    JOIN public.profiles pr ON pr.id = ppa.profile_id
    WHERE ppa.partner_id = p_partner_id
      AND ppa.is_active = true
      AND coalesce(ppa.account_kind, case when ppa.partner_vehicle_id is null then 'owner' else 'driver' end) = 'owner'
      AND pr.is_active = true
      AND coalesce(pr.is_approved, false) = true
      AND pr.phone IS NOT NULL
    UNION ALL
    SELECT pr.phone
    FROM public.profiles pr
    JOIN public.partners p ON p.id = pr.partner_id AND p.is_active = true
    WHERE pr.partner_id = p_partner_id
      AND pr.partner_vehicle_id IS NULL
      AND pr.is_active = true
      AND coalesce(pr.is_approved, false) = true
      AND pr.phone IS NOT NULL
  ) src
  WHERE public.normalize_phone_no(src.phone) IS NOT NULL;
$$;

GRANT EXECUTE ON FUNCTION public.partner_owner_sms_phones(UUID) TO authenticated, service_role;

-- ── Låntaker er alltid MAVI Logistikk AS ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.resolve_mavi_borrower_partner_id(p_company_id UUID)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id
  FROM public.partners p
  WHERE p.company_id = p_company_id
    AND p.is_active = true
    AND (
      lower(trim(p.name)) = 'mavi logistikk as'
      OR lower(trim(p.name)) LIKE 'mavi logistikk%'
    )
  ORDER BY CASE WHEN lower(trim(p.name)) = 'mavi logistikk as' THEN 0 ELSE 1 END
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_mavi_borrower_partner_id(UUID) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.trg_vehicle_rentals_set_borrower()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_borrower UUID;
BEGIN
  v_borrower := public.resolve_mavi_borrower_partner_id(NEW.company_id);
  IF v_borrower IS NULL THEN
    RAISE EXCEPTION 'Fant ikke aktiv samarbeidspartner «MAVI Logistikk AS» som låntaker';
  END IF;
  NEW.borrower_partner_id := v_borrower;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS vehicle_rentals_set_borrower ON public.vehicle_rentals;
CREATE TRIGGER vehicle_rentals_set_borrower
  BEFORE INSERT ON public.vehicle_rentals
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_vehicle_rentals_set_borrower();

-- ── Tilganger bilutleie ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.user_can_manage_vehicle_rentals()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_settings JSONB;
  v_role TEXT;
  v_partner_id UUID;
  v_active BOOLEAN;
  v_approved BOOLEAN;
BEGIN
  SELECT access_settings, role::text, partner_id, is_active, is_approved
  INTO v_settings, v_role, v_partner_id, v_active, v_approved
  FROM public.profiles
  WHERE id = auth.uid();

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_role = 'superadmin' THEN
    RETURN true;
  END IF;

  IF v_partner_id IS NOT NULL THEN
    RETURN false;
  END IF;

  IF NOT coalesce(v_active, false) OR NOT coalesce(v_approved, false) THEN
    RETURN false;
  END IF;

  RETURN COALESCE((v_settings ->> 'partners_vehicle_rental')::boolean, false)
    OR COALESCE((v_settings ->> 'partners_admin')::boolean, false)
    OR COALESCE((v_settings ->> 'fleet_ruter')::boolean, false);
END;
$$;

CREATE OR REPLACE FUNCTION public.user_can_approve_vehicle_rentals()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_settings JSONB;
  v_role TEXT;
  v_partner_id UUID;
  v_active BOOLEAN;
  v_approved BOOLEAN;
BEGIN
  SELECT access_settings, role::text, partner_id, is_active, is_approved
  INTO v_settings, v_role, v_partner_id, v_active, v_approved
  FROM public.profiles
  WHERE id = auth.uid();

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_role = 'superadmin' THEN
    RETURN true;
  END IF;

  IF v_partner_id IS NOT NULL THEN
    RETURN false;
  END IF;

  IF NOT coalesce(v_active, false) OR NOT coalesce(v_approved, false) THEN
    RETURN false;
  END IF;

  RETURN COALESCE((v_settings ->> 'partners_vehicle_rental_approve')::boolean, false)
    OR COALESCE((v_settings ->> 'partners_admin')::boolean, false);
END;
$$;

GRANT EXECUTE ON FUNCTION public.user_can_manage_vehicle_rentals() TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_can_approve_vehicle_rentals() TO authenticated;

-- ── SMS: møte og portal (kun aktive partnere) ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_partner_meeting_sms(
  p_partner_id UUID,
  p_message TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone TEXT;
  v_company UUID;
BEGIN
  SELECT p.phone, p.company_id
  INTO v_phone, v_company
  FROM public.partners p
  WHERE p.id = p_partner_id
    AND p.is_active = true;

  IF v_phone IS NULL OR length(trim(v_phone)) < 8 THEN
    RETURN 0;
  END IF;

  PERFORM public.queue_sms(
    v_company,
    v_phone,
    left(p_message, 1600),
    'partner_meeting',
    'partner',
    p_partner_id,
    NULL,
    NULL
  );
  RETURN 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_partner_portal_credentials_sms(
  p_company_id UUID,
  p_phone TEXT,
  p_username TEXT,
  p_password TEXT,
  p_is_owner BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  role_label TEXT := CASE WHEN p_is_owner THEN 'bil-eier' ELSE 'sjåfør' END;
  msg TEXT;
  norm_phone TEXT;
BEGIN
  norm_phone := public.normalize_phone_no(p_phone);
  IF norm_phone IS NULL THEN
    RETURN NULL;
  END IF;

  msg := 'DriftPro ' || role_label || E'\nBruker: ' || p_username ||
    E'\nPassord: ' || p_password ||
    E'\nLogg inn: driftpro.no (Samarbeidspartner)';

  RETURN public.queue_sms(
    p_company_id,
    norm_phone,
    msg,
    'partner_portal',
    'partner_portal_accounts',
    NULL
  );
END;
$$;

-- ── Rute-SMS: respekter inaktive partnere/biler/eiere ─────────────────────────
CREATE OR REPLACE FUNCTION public.notify_partner_route_assigned_sms(p_route_share_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  shift_name TEXT;
  driver_msg TEXT;
  owner_msg TEXT;
  n INT := 0;
  driver_phone TEXT;
  owner_phone TEXT;
  owner_rec RECORD;
  owner_only BOOLEAN;
  sent_phones TEXT[] := ARRAY[]::TEXT[];
BEGIN
  SELECT
    prs.*,
    pv.unit_code,
    pv.registration_number AS vehicle_reg,
    p.phone AS partner_phone,
    p.name AS partner_name,
    p.is_active AS partner_is_active,
    coalesce(p.routes_owner_only, true) AS routes_owner_only
  INTO r
  FROM public.partner_route_shares prs
  LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
  LEFT JOIN public.partners p ON p.id = prs.partner_id
  WHERE prs.id = p_route_share_id;

  IF r IS NULL OR coalesce(r.partner_is_active, false) = false THEN
    RETURN 0;
  END IF;

  IF r.partner_vehicle_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.partner_vehicles pv2
      WHERE pv2.id = r.partner_vehicle_id AND pv2.is_active = true
    ) THEN
      RETURN 0;
    END IF;
  END IF;

  IF coalesce(r.dispatch_status, 'sent') <> 'sent' THEN
    RETURN 0;
  END IF;

  owner_only := coalesce(r.routes_owner_only, true);

  SELECT name INTO shift_name FROM public.fleet_shift_definitions WHERE id = r.shift_id;

  driver_msg := 'Ny rute tildelt ' || coalesce(r.unit_code, '') ||
    CASE WHEN r.vehicle_reg IS NOT NULL AND trim(r.vehicle_reg) <> '' THEN ' (' || trim(r.vehicle_reg) || ')' ELSE '' END ||
    CASE WHEN shift_name IS NOT NULL THEN ' · Skift: ' || shift_name ELSE '' END ||
    CASE WHEN r.route_start_at IS NOT NULL THEN
      ' · Start ' || to_char(r.route_start_at AT TIME ZONE 'Europe/Oslo', 'DD.MM HH24:MI')
    ELSE '' END ||
    '. Logg inn i DriftPro for PDF og aksept.';

  owner_msg := 'Ny rute på ' || coalesce(r.unit_code, 'bil') ||
    CASE WHEN r.vehicle_reg IS NOT NULL AND trim(r.vehicle_reg) <> '' THEN ' (' || trim(r.vehicle_reg) || ')' ELSE '' END ||
    ' — ' || coalesce(r.partner_name, 'din bedrift') ||
    CASE WHEN shift_name IS NOT NULL THEN ' · ' || shift_name ELSE '' END ||
    CASE WHEN r.route_start_at IS NOT NULL THEN
      ' · Start ' || to_char(r.route_start_at AT TIME ZONE 'Europe/Oslo', 'DD.MM HH24:MI')
    ELSE '' END ||
    '. Logg inn i DriftPro for oversikt og godkjenning.';

  IF NOT owner_only THEN
    SELECT public.normalize_phone_no(ppa.phone) INTO driver_phone
    FROM public.partner_portal_accounts ppa
    JOIN public.partners p ON p.id = ppa.partner_id AND p.is_active = true
    WHERE ppa.partner_vehicle_id = r.partner_vehicle_id
      AND ppa.is_active = true
      AND coalesce(ppa.account_kind, 'driver') = 'driver'
      AND ppa.phone IS NOT NULL
    ORDER BY ppa.updated_at DESC NULLS LAST, ppa.created_at DESC
    LIMIT 1;

    IF driver_phone IS NOT NULL AND NOT (driver_phone = ANY (sent_phones)) THEN
      PERFORM public.queue_sms(
        r.company_id,
        driver_phone,
        driver_msg,
        'partner_route',
        'partner_route_shares',
        r.id
      );
      sent_phones := array_append(sent_phones, driver_phone);
      n := n + 1;
    END IF;
  END IF;

  FOR owner_rec IN
    SELECT pop.phone FROM public.partner_owner_sms_phones(r.partner_id) pop
  LOOP
    owner_phone := owner_rec.phone;
    IF owner_phone IS NOT NULL AND NOT (owner_phone = ANY (sent_phones)) THEN
      PERFORM public.queue_sms(
        r.company_id,
        owner_phone,
        owner_msg,
        'partner_route_owner',
        'partner_route_shares',
        r.id
      );
      sent_phones := array_append(sent_phones, owner_phone);
      n := n + 1;
    END IF;
  END LOOP;

  RETURN n;
END;
$$;

-- ── Bilutleie SMS til samarbeidspartner (bileier) ─────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_vehicle_rental_partner_sms(
  p_rental_id UUID,
  p_event TEXT
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  borrower_name TEXT;
  msg TEXT;
  owner_rec RECORD;
  n INT := 0;
  cat TEXT;
BEGIN
  SELECT
    vr.*,
    p.name AS lender_name,
    p.is_active AS lender_active
  INTO r
  FROM public.vehicle_rentals vr
  JOIN public.partners p ON p.id = vr.lender_partner_id
  WHERE vr.id = p_rental_id;

  IF r IS NULL OR coalesce(r.lender_active, false) = false THEN
    RETURN 0;
  END IF;

  IF r.partner_vehicle_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.partner_vehicles pv
      WHERE pv.id = r.partner_vehicle_id AND pv.is_active = true
    ) AND p_event IN ('created', 'approved') THEN
      RETURN 0;
    END IF;
  END IF;

  SELECT name INTO borrower_name FROM public.partners WHERE id = r.borrower_partner_id;

  msg := CASE p_event
    WHEN 'created' THEN
      'Ny bilutleie i DriftPro: '
      || coalesce(r.unit_code, 'bil')
      || coalesce(' (' || nullif(trim(r.registration_number), '') || ')', '')
      || ' skal lånes ut til '
      || coalesce(borrower_name, 'MAVI Logistikk AS')
      || '. Logg inn som bil-eier, les avtalen, ta 6 bilder og send til godkjenning.'
    WHEN 'approved' THEN
      'Bilutleie godkjent av MAVI: '
      || coalesce(r.unit_code, 'bil')
      || coalesce(' (' || nullif(trim(r.registration_number), '') || ')', '')
      || ' er utlånt til '
      || coalesce(borrower_name, 'MAVI Logistikk AS')
      || '. Overlevering kan skje.'
    WHEN 'rejected' THEN
      'Bilutleie avvist av MAVI: '
      || coalesce(r.unit_code, 'bil')
      || coalesce(' (' || nullif(trim(r.registration_number), '') || ')', '')
      || coalesce('. Årsak: ' || nullif(trim(r.rejection_reason), ''), '.')
      || ' Logg inn i DriftPro for detaljer.'
    WHEN 'return_submitted' THEN
      'Retur registrert for '
      || coalesce(r.unit_code, 'bil')
      || coalesce(' (' || nullif(trim(r.registration_number), '') || ')', '')
      || ' fra '
      || coalesce(borrower_name, 'MAVI Logistikk AS')
      || '. MAVI vurderer returen i DriftPro.'
    WHEN 'return_approved' THEN
      'Retur godkjent av MAVI: '
      || coalesce(r.unit_code, 'bil')
      || coalesce(' (' || nullif(trim(r.registration_number), '') || ')', '')
      || ' er tilbake hos utleier og tilgjengelig igjen.'
    ELSE NULL
  END;

  IF msg IS NULL THEN
    RETURN 0;
  END IF;

  cat := CASE p_event
    WHEN 'created' THEN 'vehicle_rental'
    ELSE 'vehicle_rental_status'
  END;

  FOR owner_rec IN
    SELECT pop.phone FROM public.partner_owner_sms_phones(r.lender_partner_id) pop
  LOOP
    IF owner_rec.phone IS NOT NULL THEN
      PERFORM public.queue_sms(
        r.company_id,
        owner_rec.phone,
        msg,
        cat,
        'vehicle_rentals',
        r.id
      );
      n := n + 1;
    END IF;
  END LOOP;

  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_vehicle_rental_owner_sms(p_rental_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.notify_vehicle_rental_partner_sms(p_rental_id, 'created');
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_vehicle_rental_partner_sms(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.notify_vehicle_rental_owner_sms(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.notify_partner_route_assigned_sms(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.notify_partner_meeting_sms(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.notify_partner_portal_credentials_sms(UUID, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated, service_role;

-- ── Bilutleie godkjenning (kun med tilatelse) ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.vehicle_rental_approve_checkout(
  p_rental_id UUID,
  p_comment TEXT DEFAULT NULL
)
RETURNS public.vehicle_rentals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.vehicle_rentals;
BEGIN
  IF NOT public.user_can_approve_vehicle_rentals() THEN
    RAISE EXCEPTION 'Ingen tilgang til å godkjenne bilutleie';
  END IF;

  UPDATE public.vehicle_rentals
  SET
    status = 'approved',
    approved_at = now(),
    approved_by = auth.uid(),
    mavi_checkout_comment = nullif(trim(p_comment), ''),
    updated_at = now()
  WHERE id = p_rental_id
    AND status = 'pending_mavi'
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Utleie finnes ikke eller er ikke klar for godkjenning';
  END IF;

  PERFORM public.notify_vehicle_rental_partner_sms(p_rental_id, 'approved');
  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.vehicle_rental_reject(
  p_rental_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS public.vehicle_rentals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.vehicle_rentals;
BEGIN
  IF NOT public.user_can_approve_vehicle_rentals() THEN
    RAISE EXCEPTION 'Ingen tilgang til å avvise bilutleie';
  END IF;

  UPDATE public.vehicle_rentals
  SET
    status = 'rejected',
    rejected_at = now(),
    rejection_reason = nullif(trim(p_reason), ''),
    updated_at = now()
  WHERE id = p_rental_id
    AND status IN ('pending_mavi', 'pending_owner')
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Utleie finnes ikke eller kan ikke avvises';
  END IF;

  PERFORM public.notify_vehicle_rental_partner_sms(p_rental_id, 'rejected');
  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.vehicle_rental_approve_return(
  p_rental_id UUID,
  p_comment TEXT DEFAULT NULL
)
RETURNS public.vehicle_rentals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.vehicle_rentals;
BEGIN
  IF NOT public.user_can_approve_vehicle_rentals() THEN
    RAISE EXCEPTION 'Ingen tilgang til å godkjenne retur';
  END IF;

  UPDATE public.vehicle_rentals
  SET
    status = 'returned',
    return_approved_at = now(),
    return_approved_by = auth.uid(),
    mavi_return_comment = nullif(trim(p_comment), ''),
    updated_at = now()
  WHERE id = p_rental_id
    AND status = 'pending_return_mavi'
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Retur finnes ikke eller er ikke klar for godkjenning';
  END IF;

  PERFORM public.notify_vehicle_rental_partner_sms(p_rental_id, 'return_approved');
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.vehicle_rental_approve_checkout(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.vehicle_rental_reject(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.vehicle_rental_approve_return(UUID, TEXT) TO authenticated;

-- ── Partner SMS-logg: fiks ambiguous id + bilutleie ─────────────────────────
CREATE OR REPLACE FUNCTION public.is_partner_scope_sms(
  p_category TEXT,
  p_reference_type TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    COALESCE(p_category, '') LIKE 'partner%'
    OR COALESCE(p_category, '') LIKE 'vehicle_rental%'
    OR COALESCE(p_reference_type, '') IN (
      'partners',
      'partner',
      'partner_route_shares',
      'partner_portal_accounts',
      'vehicle_rentals'
    );
$$;

CREATE OR REPLACE FUNCTION public.list_partner_sms_log(
  p_limit INT DEFAULT 50,
  p_offset INT DEFAULT 0,
  p_search TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_from_date TIMESTAMPTZ DEFAULT NULL,
  p_to_date TIMESTAMPTZ DEFAULT NULL,
  p_recipient TEXT DEFAULT NULL,
  p_sender TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT NULL,
  p_partner_id UUID DEFAULT NULL,
  p_sort TEXT DEFAULT 'created_desc'
)
RETURNS TABLE (
  id UUID,
  created_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  to_phone TEXT,
  message TEXT,
  category TEXT,
  reference_type TEXT,
  reference_id UUID,
  error_message TEXT,
  attempts INT,
  sveve_message_id BIGINT,
  recipient_name TEXT,
  recipient_user_id UUID,
  triggered_by_name TEXT,
  triggered_by_user_id UUID,
  delivery_status TEXT,
  sender_name TEXT,
  partner_name TEXT,
  context_label TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_company_id UUID;
BEGIN
  IF NOT public.user_can_view_partner_sms_log() THEN
    RAISE EXCEPTION 'Ingen tilgang til partner SMS-logg';
  END IF;

  SELECT company_id INTO v_company_id
  FROM public.profiles
  WHERE id = auth.uid();

  RETURN QUERY
  SELECT
    o.id,
    o.created_at,
    o.sent_at,
    o.to_phone,
    o.message,
    o.category,
    o.reference_type,
    o.reference_id,
    o.error_message,
    o.attempts,
    o.sveve_message_id,
    COALESCE(
      pr.full_name,
      (SELECT p2.full_name FROM public.profiles p2
       WHERE p2.phone_normalized = o.to_phone AND p2.company_id = v_company_id
       LIMIT 1),
      o.to_phone
    ) AS recipient_name,
    COALESCE(
      o.to_user_id,
      (SELECT p3.id FROM public.profiles p3
       WHERE p3.phone_normalized = o.to_phone AND p3.company_id = v_company_id
       LIMIT 1)
    ) AS recipient_user_id,
    COALESCE(pt.full_name, 'System (automatisk)') AS triggered_by_name,
    o.triggered_by_user_id,
    CASE
      WHEN o.sent_at IS NOT NULL THEN 'sendt'
      WHEN o.error_message IS NOT NULL AND o.attempts >= 3 THEN 'feilet'
      WHEN o.error_message IS NOT NULL THEN 'feil'
      ELSE 'i_ko'
    END AS delivery_status,
    'Mavi'::text AS sender_name,
    COALESCE(
      p_route.name,
      p_ref.name,
      p_meet.name,
      p_vrent.name
    ) AS partner_name,
    CASE
      WHEN o.reference_type = 'partner_route_shares' AND prs.id IS NOT NULL THEN
        'Rute ' || COALESCE(pv.unit_code, prs.title, left(prs.id::text, 8))
      WHEN o.category = 'partner_meeting' THEN 'Møte / oppfølging'
      WHEN o.category = 'partner_portal' THEN 'Portal-innlogging'
      WHEN o.category = 'partner_compose' THEN 'Manuell utsendelse'
      WHEN o.category = 'partner_route' THEN 'Rute varsling (sjåfør)'
      WHEN o.category = 'partner_route_owner' THEN 'Rute varsling (bil-eier)'
      WHEN o.category = 'vehicle_rental' THEN 'Bilutleie — ny forespørsel'
      WHEN o.category = 'vehicle_rental_status' THEN 'Bilutleie — status'
      ELSE COALESCE(o.category, 'Samarbeid')
    END AS context_label
  FROM public.sms_outbox o
  LEFT JOIN public.profiles pr ON pr.id = o.to_user_id
  LEFT JOIN public.profiles pt ON pt.id = o.triggered_by_user_id
  LEFT JOIN public.partner_route_shares prs
    ON o.reference_type = 'partner_route_shares' AND o.reference_id = prs.id
  LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
  LEFT JOIN public.partners p_route ON p_route.id = prs.partner_id
  LEFT JOIN public.partners p_ref
    ON o.reference_type IN ('partner', 'partners') AND o.reference_id = p_ref.id
  LEFT JOIN public.partners p_meet
    ON o.reference_type = 'partner' AND o.reference_id = p_meet.id
  LEFT JOIN public.vehicle_rentals vr
    ON o.reference_type = 'vehicle_rentals' AND o.reference_id = vr.id
  LEFT JOIN public.partners p_vrent ON p_vrent.id = vr.lender_partner_id
  WHERE o.company_id = v_company_id
    AND public.is_partner_scope_sms(o.category, o.reference_type)
    AND (p_category IS NULL OR o.category = p_category)
    AND (p_from_date IS NULL OR o.created_at >= p_from_date)
    AND (p_to_date IS NULL OR o.created_at <= p_to_date)
    AND (
      p_status IS NULL
      OR (p_status = 'sendt' AND o.sent_at IS NOT NULL)
      OR (p_status = 'i_ko' AND o.sent_at IS NULL AND (o.error_message IS NULL OR o.attempts < 3))
      OR (p_status = 'feilet' AND o.sent_at IS NULL AND o.attempts >= 3)
    )
    AND (
      p_phone IS NULL OR length(trim(p_phone)) = 0
      OR o.to_phone ILIKE '%' || regexp_replace(trim(p_phone), '[^0-9+]', '', 'g') || '%'
    )
    AND (
      p_recipient IS NULL OR length(trim(p_recipient)) = 0
      OR COALESCE(pr.full_name, '') ILIKE '%' || trim(p_recipient) || '%'
      OR o.to_phone ILIKE '%' || trim(p_recipient) || '%'
    )
    AND (
      p_sender IS NULL OR length(trim(p_sender)) = 0
      OR COALESCE(pt.full_name, '') ILIKE '%' || trim(p_sender) || '%'
      OR 'Mavi' ILIKE '%' || trim(p_sender) || '%'
    )
    AND (
      p_search IS NULL OR length(trim(p_search)) = 0
      OR o.message ILIKE '%' || trim(p_search) || '%'
      OR COALESCE(o.category, '') ILIKE '%' || trim(p_search) || '%'
      OR COALESCE(p_route.name, p_ref.name, p_meet.name, p_vrent.name, '') ILIKE '%' || trim(p_search) || '%'
      OR COALESCE(pv.unit_code, vr.unit_code, '') ILIKE '%' || trim(p_search) || '%'
    )
    AND (
      p_partner_id IS NULL
      OR prs.partner_id = p_partner_id
      OR p_ref.id = p_partner_id
      OR p_meet.id = p_partner_id
      OR vr.lender_partner_id = p_partner_id
    )
  ORDER BY
    CASE WHEN p_sort = 'created_asc' THEN o.created_at END ASC,
    CASE WHEN p_sort = 'sent_desc' THEN o.sent_at END DESC NULLS LAST,
    CASE WHEN p_sort = 'sent_asc' THEN o.sent_at END ASC NULLS LAST,
    CASE WHEN p_sort = 'recipient_asc' THEN COALESCE(pr.full_name, o.to_phone) END ASC,
    CASE WHEN p_sort = 'recipient_desc' THEN COALESCE(pr.full_name, o.to_phone) END DESC,
    o.created_at DESC
  LIMIT greatest(p_limit, 1)
  OFFSET greatest(p_offset, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.count_partner_sms_log(
  p_search TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_from_date TIMESTAMPTZ DEFAULT NULL,
  p_to_date TIMESTAMPTZ DEFAULT NULL,
  p_recipient TEXT DEFAULT NULL,
  p_sender TEXT DEFAULT NULL,
  p_phone TEXT DEFAULT NULL,
  p_partner_id UUID DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_company_id UUID;
  c BIGINT;
BEGIN
  IF NOT public.user_can_view_partner_sms_log() THEN
    RETURN 0;
  END IF;

  SELECT company_id INTO v_company_id
  FROM public.profiles
  WHERE id = auth.uid();

  SELECT count(*)::bigint INTO c
  FROM public.sms_outbox o
  LEFT JOIN public.profiles pr ON pr.id = o.to_user_id
  LEFT JOIN public.profiles pt ON pt.id = o.triggered_by_user_id
  LEFT JOIN public.partner_route_shares prs
    ON o.reference_type = 'partner_route_shares' AND o.reference_id = prs.id
  LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
  LEFT JOIN public.partners p_ref
    ON o.reference_type IN ('partner', 'partners') AND o.reference_id = p_ref.id
  LEFT JOIN public.partners p_meet
    ON o.reference_type = 'partner' AND o.reference_id = p_meet.id
  LEFT JOIN public.partners p_route ON p_route.id = prs.partner_id
  LEFT JOIN public.vehicle_rentals vr
    ON o.reference_type = 'vehicle_rentals' AND o.reference_id = vr.id
  WHERE o.company_id = v_company_id
    AND public.is_partner_scope_sms(o.category, o.reference_type)
    AND (p_category IS NULL OR o.category = p_category)
    AND (p_from_date IS NULL OR o.created_at >= p_from_date)
    AND (p_to_date IS NULL OR o.created_at <= p_to_date)
    AND (
      p_status IS NULL
      OR (p_status = 'sendt' AND o.sent_at IS NOT NULL)
      OR (p_status = 'i_ko' AND o.sent_at IS NULL AND (o.error_message IS NULL OR o.attempts < 3))
      OR (p_status = 'feilet' AND o.sent_at IS NULL AND o.attempts >= 3)
    )
    AND (
      p_phone IS NULL OR length(trim(p_phone)) = 0
      OR o.to_phone ILIKE '%' || regexp_replace(trim(p_phone), '[^0-9+]', '', 'g') || '%'
    )
    AND (
      p_recipient IS NULL OR length(trim(p_recipient)) = 0
      OR COALESCE(pr.full_name, '') ILIKE '%' || trim(p_recipient) || '%'
      OR o.to_phone ILIKE '%' || trim(p_recipient) || '%'
    )
    AND (
      p_sender IS NULL OR length(trim(p_sender)) = 0
      OR COALESCE(pt.full_name, '') ILIKE '%' || trim(p_sender) || '%'
      OR 'Mavi' ILIKE '%' || trim(p_sender) || '%'
    )
    AND (
      p_search IS NULL OR length(trim(p_search)) = 0
      OR o.message ILIKE '%' || trim(p_search) || '%'
      OR COALESCE(o.category, '') ILIKE '%' || trim(p_search) || '%'
      OR COALESCE(p_route.name, p_ref.name, p_meet.name, '') ILIKE '%' || trim(p_search) || '%'
      OR COALESCE(pv.unit_code, vr.unit_code, '') ILIKE '%' || trim(p_search) || '%'
    )
    AND (
      p_partner_id IS NULL
      OR prs.partner_id = p_partner_id
      OR p_ref.id = p_partner_id
      OR p_meet.id = p_partner_id
      OR vr.lender_partner_id = p_partner_id
    );

  RETURN c;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_sms_outbox_vehicle_rental_category
  ON public.sms_outbox(company_id, created_at DESC)
  WHERE category LIKE 'vehicle_rental%';
