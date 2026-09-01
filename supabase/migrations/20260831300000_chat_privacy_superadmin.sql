-- Chat personvern + superadmin-kontroll:
-- • Partnere ser kun andre partnere (via RPC, ikke direkte SELECT)
-- • MAVI ser kun andre MAVI — aldri partnerliste/bedrifter
-- • Kun superadmin kan opprette MAVI ↔ partner-kobling
-- • Partnere kan blokkere hverandre

-- ── Kun superadmin kobler MAVI ↔ partner ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_can_send_direct_to_partner(p_uid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.get_user_role() = 'superadmin'::public.user_role;
$$;

CREATE OR REPLACE FUNCTION public.create_mavi_partner_direct_chat(p_partner_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_company_id UUID;
  v_room_id UUID;
  rec RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  IF public.get_user_role() <> 'superadmin'::public.user_role THEN
    RAISE EXCEPTION 'Kun superadmin kan koble MAVI og partner sammen';
  END IF;

  v_company_id := public.chat_user_company_id(v_uid);

  IF NOT EXISTS (
    SELECT 1 FROM public.partners p
    WHERE p.id = p_partner_id AND p.company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'Partner tilhører ikke bedriften';
  END IF;

  SELECT cr.id INTO v_room_id
  FROM public.chat_rooms cr
  WHERE cr.room_type = 'mavi_partner_direct'
    AND cr.company_id = v_company_id
    AND cr.partner_id = p_partner_id
    AND cr.is_archived IS NOT TRUE
  LIMIT 1;

  IF v_room_id IS NOT NULL THEN
    RETURN v_room_id;
  END IF;

  INSERT INTO public.chat_rooms (company_id, room_type, title, created_by, partner_id)
  VALUES (
    v_company_id,
    'mavi_partner_direct',
    (SELECT name FROM public.partners WHERE id = p_partner_id),
    v_uid,
    p_partner_id
  )
  RETURNING id INTO v_room_id;

  INSERT INTO public.chat_room_members (room_id, user_id, member_role)
  VALUES (v_room_id, v_uid, 'owner')
  ON CONFLICT DO NOTHING;

  FOR rec IN
    SELECT ppa.profile_id, ppa.partner_id
    FROM public.partner_portal_accounts ppa
    WHERE ppa.partner_id = p_partner_id
      AND coalesce(ppa.is_active, TRUE)
  LOOP
    INSERT INTO public.chat_room_members (room_id, user_id, partner_id, member_role)
    VALUES (v_room_id, rec.profile_id, rec.partner_id, 'member')
    ON CONFLICT DO NOTHING;
  END LOOP;

  INSERT INTO public.chat_audit_log (company_id, actor_id, action, room_id, meta)
  VALUES (
    v_company_id,
    v_uid,
    'superadmin_bridge_partner',
    v_room_id,
    jsonb_build_object('partner_id', p_partner_id)
  );

  RETURN v_room_id;
END;
$$;

-- ── Partner ↔ partner blokkering ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_partner_block_user(
  p_blocked_user_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_company UUID;
  v_id UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Ikke innlogget'; END IF;
  IF NOT public.chat_user_is_partner_portal(v_uid) THEN
    RAISE EXCEPTION 'Kun partnere kan bruke partner-blokkering';
  END IF;
  IF p_blocked_user_id = v_uid THEN
    RAISE EXCEPTION 'Kan ikke blokkere deg selv';
  END IF;
  IF NOT public.chat_user_is_partner_portal(p_blocked_user_id) THEN
    RAISE EXCEPTION 'Kan bare blokkere andre partnere';
  END IF;

  v_company := public.chat_user_company_id(v_uid);
  IF v_company IS DISTINCT FROM public.chat_user_company_id(p_blocked_user_id) THEN
    RAISE EXCEPTION 'Ugyldig motpart';
  END IF;

  INSERT INTO public.chat_user_blocks (
    company_id, blocked_user_id, blocked_by, scope, reason
  )
  VALUES (
    v_company,
    p_blocked_user_id,
    v_uid,
    'global',
    nullif(trim(p_reason), '')
  )
  ON CONFLICT (blocked_user_id, scope, room_id) DO UPDATE
    SET blocked_by = EXCLUDED.blocked_by,
        reason = EXCLUDED.reason,
        blocked_until = NULL
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.chat_partner_unblock_user(p_blocked_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Ikke innlogget'; END IF;

  DELETE FROM public.chat_user_blocks b
  WHERE b.blocked_user_id = p_blocked_user_id
    AND b.blocked_by = v_uid
    AND b.scope = 'global';
END;
$$;

CREATE OR REPLACE FUNCTION public.chat_users_block_each_other(p_a UUID, p_b UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.chat_user_blocks b
    WHERE b.scope = 'global'
      AND (b.blocked_until IS NULL OR b.blocked_until > now())
      AND (
        (b.blocked_user_id = p_a AND b.blocked_by = p_b)
        OR (b.blocked_user_id = p_b AND b.blocked_by = p_a)
      )
  );
$$;

-- ── Katalog-RPC (personvern) ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_partner_directory()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_company UUID;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  IF NOT public.chat_user_is_partner_portal(v_uid) THEN
    RAISE EXCEPTION 'Kun for partnerportal';
  END IF;

  v_company := public.chat_user_company_id(v_uid);

  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'user_id', ppa.profile_id,
      'full_name', coalesce(nullif(trim(p.full_name), ''), 'Partner'),
      'partner_id', ppa.partner_id,
      'partner_name', coalesce(nullif(trim(pt.name), ''), 'Partner'),
      'account_kind', coalesce(ppa.account_kind, 'owner')
    ) ORDER BY pt.name, p.full_name)
    FROM public.partner_portal_accounts ppa
    JOIN public.profiles p ON p.id = ppa.profile_id
    JOIN public.partners pt ON pt.id = ppa.partner_id
    WHERE coalesce(ppa.is_active, TRUE)
      AND coalesce(p.is_active, TRUE)
      AND pt.company_id = v_company
      AND ppa.profile_id <> v_uid
      AND NOT public.chat_users_block_each_other(v_uid, ppa.profile_id)
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.chat_mavi_directory()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_company UUID;
BEGIN
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;
  IF NOT public.chat_user_is_mavi_employee(v_uid) THEN
    RAISE EXCEPTION 'Kun for MAVI-ansatte';
  END IF;

  v_company := public.chat_user_company_id(v_uid);

  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'user_id', p.id,
      'full_name', coalesce(nullif(trim(p.full_name), ''), 'Ansatt')
    ) ORDER BY p.full_name)
    FROM public.profiles p
    WHERE p.company_id = v_company
      AND coalesce(p.is_active, TRUE)
      AND p.id <> v_uid
      AND NOT public.chat_user_is_partner_portal(p.id)
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.chat_superadmin_directory()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_company UUID;
BEGIN
  IF public.get_user_role() <> 'superadmin'::public.user_role THEN
    RAISE EXCEPTION 'Kun superadmin';
  END IF;

  v_company := public.chat_user_company_id(v_uid);

  RETURN jsonb_build_object(
    'mavi', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', p.id,
        'full_name', coalesce(nullif(trim(p.full_name), ''), 'MAVI')
      ) ORDER BY p.full_name)
      FROM public.profiles p
      WHERE p.company_id = v_company
        AND coalesce(p.is_active, TRUE)
        AND NOT public.chat_user_is_partner_portal(p.id)
    ), '[]'::jsonb),
    'partners', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', ppa.profile_id,
        'full_name', coalesce(nullif(trim(p.full_name), ''), 'Partner'),
        'partner_id', ppa.partner_id,
        'partner_name', coalesce(nullif(trim(pt.name), ''), 'Partner'),
        'account_kind', coalesce(ppa.account_kind, 'owner')
      ) ORDER BY pt.name, p.full_name)
      FROM public.partner_portal_accounts ppa
      JOIN public.profiles p ON p.id = ppa.profile_id
      JOIN public.partners pt ON pt.id = ppa.partner_id
      WHERE coalesce(ppa.is_active, TRUE)
        AND pt.company_id = v_company
    ), '[]'::jsonb),
    'companies', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'partner_id', pt.id,
        'partner_name', pt.name,
        'owner_name', pt.owner_name
      ) ORDER BY pt.name)
      FROM public.partners pt
      WHERE pt.company_id = v_company
        AND coalesce(pt.is_active, TRUE)
    ), '[]'::jsonb)
  );
END;
$$;

-- Superadmin: opprett grupper på vegne av MAVI eller partnere
CREATE OR REPLACE FUNCTION public.chat_superadmin_create_mavi_group(
  p_member_ids UUID[],
  p_title TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_company UUID;
  v_room_id UUID;
  mid UUID;
BEGIN
  IF public.get_user_role() <> 'superadmin'::public.user_role THEN
    RAISE EXCEPTION 'Kun superadmin';
  END IF;
  v_company := public.chat_user_company_id(v_uid);

  INSERT INTO public.chat_rooms (company_id, room_type, title, created_by)
  VALUES (v_company, 'mavi_group', trim(p_title), v_uid)
  RETURNING id INTO v_room_id;

  INSERT INTO public.chat_room_members (room_id, user_id, member_role)
  VALUES (v_room_id, v_uid, 'owner') ON CONFLICT DO NOTHING;

  FOREACH mid IN ARRAY coalesce(p_member_ids, ARRAY[]::UUID[])
  LOOP
    IF public.chat_user_is_mavi_employee(mid)
       AND public.chat_user_company_id(mid) = v_company THEN
      INSERT INTO public.chat_room_members (room_id, user_id, member_role)
      VALUES (v_room_id, mid, 'member') ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;

  RETURN v_room_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.chat_superadmin_create_partner_group(
  p_member_ids UUID[],
  p_title TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_company UUID;
  v_room_id UUID;
  mid UUID;
  v_count INT := 0;
BEGIN
  IF public.get_user_role() <> 'superadmin'::public.user_role THEN
    RAISE EXCEPTION 'Kun superadmin';
  END IF;
  v_company := public.chat_user_company_id(v_uid);

  INSERT INTO public.chat_rooms (company_id, room_type, title, created_by)
  VALUES (v_company, 'partner_group', trim(p_title), v_uid)
  RETURNING id INTO v_room_id;

  FOREACH mid IN ARRAY coalesce(p_member_ids, ARRAY[]::UUID[])
  LOOP
    IF public.chat_user_is_partner_portal(mid)
       AND public.chat_user_company_id(mid) = v_company
       AND NOT public.chat_user_is_blocked(mid) THEN
      INSERT INTO public.chat_room_members (room_id, user_id, partner_id, member_role)
      VALUES (v_room_id, mid, public.chat_user_partner_id(mid), 'member')
      ON CONFLICT DO NOTHING;
      v_count := v_count + 1;
    END IF;
  END LOOP;

  IF v_count < 2 THEN
    RAISE EXCEPTION 'Partner-gruppe må ha minst 2 medlemmer';
  END IF;

  RETURN v_room_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.chat_superadmin_invite_to_room(
  p_room_id UUID,
  p_user_ids UUID[]
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  r public.chat_rooms%ROWTYPE;
  mid UUID;
  added INT := 0;
BEGIN
  IF public.get_user_role() <> 'superadmin'::public.user_role THEN
    RAISE EXCEPTION 'Kun superadmin';
  END IF;

  SELECT * INTO r FROM public.chat_rooms WHERE id = p_room_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Rom finnes ikke'; END IF;

  FOREACH mid IN ARRAY coalesce(p_user_ids, ARRAY[]::UUID[])
  LOOP
    IF r.room_type IN ('mavi_internal', 'mavi_group')
       AND public.chat_user_is_mavi_employee(mid) THEN
      INSERT INTO public.chat_room_members (room_id, user_id, member_role)
      VALUES (p_room_id, mid, 'member') ON CONFLICT DO NOTHING;
      added := added + 1;
    ELSIF r.room_type IN ('partner_private', 'partner_group')
       AND public.chat_user_is_partner_portal(mid) THEN
      INSERT INTO public.chat_room_members (room_id, user_id, partner_id, member_role)
      VALUES (p_room_id, mid, public.chat_user_partner_id(mid), 'member')
      ON CONFLICT DO NOTHING;
      added := added + 1;
    END IF;
  END LOOP;

  RETURN added;
END;
$$;

GRANT EXECUTE ON FUNCTION public.chat_partner_directory() TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_mavi_directory() TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_superadmin_directory() TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_partner_block_user(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_partner_unblock_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_superadmin_create_mavi_group(UUID[], TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_superadmin_create_partner_group(UUID[], TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_superadmin_invite_to_room(UUID, UUID[]) TO authenticated;
