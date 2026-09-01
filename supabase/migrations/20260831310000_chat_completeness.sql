-- Chat completeness: uleste, pin/demp, moderering, partner blokkliste, sletting.

-- ── Pin / demp ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_set_room_pinned(p_room_id UUID, p_pinned BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Ikke innlogget'; END IF;
  IF NOT public.chat_user_can_access_room(v_uid, p_room_id) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  INSERT INTO public.chat_user_room_prefs (room_id, user_id, pinned_at, updated_at)
  VALUES (p_room_id, v_uid, CASE WHEN p_pinned THEN now() ELSE NULL END, now())
  ON CONFLICT (room_id, user_id) DO UPDATE
    SET pinned_at = CASE WHEN p_pinned THEN now() ELSE NULL END,
        updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.chat_set_room_muted(
  p_room_id UUID,
  p_muted BOOLEAN,
  p_hours INT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid UUID := auth.uid();
DECLARE v_until TIMESTAMPTZ;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Ikke innlogget'; END IF;
  IF NOT public.chat_user_can_access_room(v_uid, p_room_id) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  IF p_muted THEN
    v_until := CASE
      WHEN p_hours IS NOT NULL AND p_hours > 0 THEN now() + make_interval(hours => p_hours)
      ELSE 'infinity'::timestamptz
    END;
  ELSE
    v_until := NULL;
  END IF;

  INSERT INTO public.chat_user_room_prefs (room_id, user_id, muted_until, updated_at)
  VALUES (p_room_id, v_uid, v_until, now())
  ON CONFLICT (room_id, user_id) DO UPDATE
    SET muted_until = v_until,
        updated_at = now();
END;
$$;

-- ── Uleste meldinger ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_my_unread_by_room()
RETURNS TABLE(room_id UUID, unread_count BIGINT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT r.id AS room_id,
    count(m.id)::bigint AS unread_count
  FROM public.chat_rooms r
  LEFT JOIN public.chat_read_state rs
    ON rs.room_id = r.id AND rs.user_id = auth.uid()
  LEFT JOIN public.chat_messages m
    ON m.room_id = r.id
    AND m.sender_id IS DISTINCT FROM auth.uid()
    AND m.moderation_state = 'active'
    AND m.deleted_at IS NULL
    AND (rs.last_read_at IS NULL OR m.created_at > rs.last_read_at)
  WHERE public.chat_user_can_access_room(auth.uid(), r.id)
  GROUP BY r.id;
$$;

CREATE OR REPLACE FUNCTION public.chat_total_unread_count()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(sum(u.unread_count), 0)::bigint
  FROM public.chat_my_unread_by_room() u;
$$;

-- ── Partner blokkliste ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_partner_blocked_list()
RETURNS TABLE(
  user_id UUID,
  full_name TEXT,
  blocked_at TIMESTAMPTZ,
  reason TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    b.blocked_user_id,
    coalesce(nullif(trim(p.full_name), ''), 'Bruker'),
    b.created_at,
    b.reason
  FROM public.chat_user_blocks b
  JOIN public.profiles p ON p.id = b.blocked_user_id
  WHERE b.blocked_by = auth.uid()
    AND b.scope = 'global'
    AND (b.blocked_until IS NULL OR b.blocked_until > now())
  ORDER BY b.created_at DESC;
$$;

-- ── Moderering ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_hide_message(p_message_id UUID)
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
  SET moderation_state = 'hidden',
      blocked_by = v_uid,
      updated_at = now()
  WHERE id = p_message_id;

  v_company := public.chat_user_company_id(v_uid);

  INSERT INTO public.chat_audit_log (company_id, actor_id, action, room_id, message_id)
  VALUES (v_company, v_uid, 'hide_message', v_room, p_message_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.chat_delete_own_message(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Ikke innlogget'; END IF;

  UPDATE public.chat_messages
  SET deleted_at = now(),
      body = '[Slettet]',
      updated_at = now()
  WHERE id = p_message_id
    AND sender_id = v_uid
    AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kan ikke slette denne meldingen';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.chat_moderation_audit_log(p_limit INT DEFAULT 50)
RETURNS SETOF public.chat_audit_log
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT *
  FROM public.chat_audit_log
  WHERE public.chat_can_moderate(auth.uid())
  ORDER BY created_at DESC
  LIMIT greatest(1, least(coalesce(p_limit, 50), 200));
$$;

CREATE OR REPLACE FUNCTION public.chat_message_read_by(
  p_room_id UUID,
  p_message_id UUID
)
RETURNS TABLE(user_id UUID, full_name TEXT, read_at TIMESTAMPTZ)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    rs.user_id,
    coalesce(nullif(trim(p.full_name), ''), 'Bruker'),
    rs.last_read_at
  FROM public.chat_read_state rs
  JOIN public.profiles p ON p.id = rs.user_id
  JOIN public.chat_messages msg ON msg.id = p_message_id
  WHERE rs.room_id = p_room_id
    AND rs.user_id IS DISTINCT FROM msg.sender_id
    AND rs.last_read_at >= msg.created_at
    AND public.chat_user_can_access_room(auth.uid(), p_room_id)
  ORDER BY rs.last_read_at ASC;
$$;

GRANT EXECUTE ON FUNCTION public.chat_set_room_pinned(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_set_room_muted(UUID, BOOLEAN, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_my_unread_by_room() TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_total_unread_count() TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_partner_blocked_list() TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_hide_message(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_delete_own_message(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_moderation_audit_log(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_message_read_by(UUID, UUID) TO authenticated;
