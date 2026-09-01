-- Fix superadmin/moderator send i partner-grupper, moderator slett melding,
-- partnere kan ikke blokkere MAVI/superadmin.

CREATE OR REPLACE FUNCTION public.chat_user_can_send(p_uid UUID, p_room_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r public.chat_rooms%ROWTYPE;
  mem public.chat_room_members%ROWTYPE;
BEGIN
  IF p_uid IS NULL OR p_room_id IS NULL THEN RETURN FALSE; END IF;

  IF public.chat_can_moderate(p_uid)
     AND public.chat_user_can_access_room(p_uid, p_room_id) THEN
    RETURN TRUE;
  END IF;

  IF NOT public.chat_user_can_access_room(p_uid, p_room_id) THEN RETURN FALSE; END IF;
  IF public.chat_user_is_blocked(p_uid, p_room_id) THEN RETURN FALSE; END IF;

  SELECT * INTO r FROM public.chat_rooms WHERE id = p_room_id;
  SELECT * INTO mem FROM public.chat_room_members
  WHERE room_id = p_room_id AND user_id = p_uid AND left_at IS NULL;

  CASE r.room_type
    WHEN 'mavi_internal', 'mavi_group' THEN
      RETURN public.chat_user_is_mavi_employee(p_uid)
        AND (mem.member_role IS NULL OR mem.member_role <> 'readonly');
    WHEN 'partner_broadcast' THEN
      RETURN public.chat_can_send_broadcast(p_uid);
    WHEN 'partner_private', 'partner_group' THEN
      RETURN public.chat_user_is_partner_portal(p_uid)
        AND mem.user_id IS NOT NULL
        AND (mem.member_role IS NULL OR mem.member_role <> 'readonly');
    WHEN 'mavi_partner_direct' THEN
      IF public.chat_user_is_partner_portal(p_uid) THEN
        RETURN mem.member_role IS NULL OR mem.member_role <> 'readonly';
      END IF;
      RETURN public.chat_can_send_direct_to_partner(p_uid);
    ELSE RETURN FALSE;
  END CASE;
END;
$$;

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
  blocked_role public.user_role;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Ikke innlogget'; END IF;
  IF NOT public.chat_user_is_partner_portal(v_uid) THEN
    RAISE EXCEPTION 'Kun partnere kan bruke partner-blokkering';
  END IF;
  IF p_blocked_user_id = v_uid THEN
    RAISE EXCEPTION 'Kan ikke blokkere deg selv';
  END IF;
  IF NOT public.chat_user_is_partner_portal(p_blocked_user_id) THEN
    RAISE EXCEPTION 'Kan bare blokkere andre partnere — ikke MAVI eller superadmin';
  END IF;

  SELECT role INTO blocked_role FROM public.profiles WHERE id = p_blocked_user_id;
  IF blocked_role = 'superadmin'::public.user_role THEN
    RAISE EXCEPTION 'Kan ikke blokkere superadmin';
  END IF;
  IF public.chat_user_is_mavi_employee(p_blocked_user_id) THEN
    RAISE EXCEPTION 'Kan ikke blokkere MAVI-ansatte';
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

CREATE OR REPLACE FUNCTION public.chat_moderator_delete_message(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_room UUID;
  v_company UUID;
BEGIN
  IF NOT public.chat_can_moderate(v_uid) THEN
    RAISE EXCEPTION 'Kun moderator/superadmin';
  END IF;

  SELECT m.room_id INTO v_room
  FROM public.chat_messages m WHERE m.id = p_message_id;

  IF v_room IS NULL THEN RAISE EXCEPTION 'Melding ikke funnet'; END IF;

  UPDATE public.chat_messages
  SET deleted_at = now(),
      body = '[Slettet av moderator]',
      moderation_state = 'hidden',
      blocked_by = v_uid,
      updated_at = now()
  WHERE id = p_message_id;

  v_company := public.chat_user_company_id(v_uid);

  INSERT INTO public.chat_audit_log (company_id, actor_id, action, room_id, message_id)
  VALUES (v_company, v_uid, 'delete_message', v_room, p_message_id);
END;
$$;

-- Superadmin opprettet partner-gruppe: legg superadmin inn som observerende eier (kan sende via moderator)
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

  INSERT INTO public.chat_room_members (room_id, user_id, member_role)
  VALUES (v_room_id, v_uid, 'owner')
  ON CONFLICT DO NOTHING;

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

GRANT EXECUTE ON FUNCTION public.chat_moderator_delete_message(UUID) TO authenticated;
