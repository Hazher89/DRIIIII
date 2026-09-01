-- Avansert chat-admin: medlemsliste, fjern medlem, slett rom, forlat rom.

CREATE OR REPLACE FUNCTION public.chat_room_members_list(p_room_id UUID)
RETURNS TABLE(
  user_id UUID,
  full_name TEXT,
  member_role TEXT,
  partner_name TEXT,
  account_kind TEXT,
  joined_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    m.user_id,
    coalesce(nullif(trim(p.full_name), ''), 'Bruker'),
    m.member_role::text,
    coalesce(pt.name, ''),
    CASE
      WHEN public.chat_user_is_mavi_employee(m.user_id) THEN 'mavi'
      WHEN EXISTS (
        SELECT 1 FROM public.partner_portal_accounts ppa
        WHERE ppa.profile_id = m.user_id AND coalesce(ppa.is_active, true)
          AND ppa.account_kind = 'driver'
      ) THEN 'driver'
      WHEN EXISTS (
        SELECT 1 FROM public.partner_portal_accounts ppa
        WHERE ppa.profile_id = m.user_id AND coalesce(ppa.is_active, true)
          AND ppa.account_kind = 'staff'
      ) THEN 'staff'
      ELSE 'owner'
    END,
    m.joined_at
  FROM public.chat_room_members m
  JOIN public.profiles p ON p.id = m.user_id
  LEFT JOIN public.partners pt ON pt.id = m.partner_id
  WHERE m.room_id = p_room_id
    AND m.left_at IS NULL
    AND public.chat_user_can_access_room(auth.uid(), p_room_id)
  ORDER BY m.joined_at ASC;
$$;

CREATE OR REPLACE FUNCTION public.chat_superadmin_remove_from_room(
  p_room_id UUID,
  p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  r public.chat_rooms%ROWTYPE;
BEGIN
  IF public.get_user_role() <> 'superadmin'::public.user_role THEN
    RAISE EXCEPTION 'Kun superadmin';
  END IF;

  SELECT * INTO r FROM public.chat_rooms WHERE id = p_room_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Rom finnes ikke'; END IF;
  IF r.room_type = 'partner_broadcast' THEN
    RAISE EXCEPTION 'Kan ikke fjerne fra broadcast-kanalen';
  END IF;

  UPDATE public.chat_room_members
  SET left_at = now()
  WHERE room_id = p_room_id
    AND user_id = p_user_id
    AND left_at IS NULL;

  INSERT INTO public.chat_audit_log (company_id, actor_id, action, room_id, target_user_id)
  VALUES (r.company_id, v_uid, 'remove_member', p_room_id, p_user_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.chat_superadmin_delete_room(p_room_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  r public.chat_rooms%ROWTYPE;
BEGIN
  IF public.get_user_role() <> 'superadmin'::public.user_role THEN
    RAISE EXCEPTION 'Kun superadmin';
  END IF;

  SELECT * INTO r FROM public.chat_rooms WHERE id = p_room_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Rom finnes ikke'; END IF;
  IF r.room_type = 'partner_broadcast' THEN
    RAISE EXCEPTION 'Broadcast-kanalen kan ikke slettes';
  END IF;

  INSERT INTO public.chat_audit_log (company_id, actor_id, action, room_id, meta)
  VALUES (
    r.company_id,
    v_uid,
    'delete_room',
    p_room_id,
    jsonb_build_object('room_type', r.room_type, 'title', r.title)
  );

  DELETE FROM public.chat_rooms WHERE id = p_room_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.chat_leave_room(p_room_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r public.chat_rooms%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Ikke innlogget'; END IF;

  SELECT * INTO r FROM public.chat_rooms WHERE id = p_room_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Rom finnes ikke'; END IF;
  IF r.room_type = 'partner_broadcast' THEN
    RAISE EXCEPTION 'Kan ikke forlate broadcast-kanalen';
  END IF;

  UPDATE public.chat_room_members
  SET left_at = now()
  WHERE room_id = p_room_id
    AND user_id = auth.uid()
    AND left_at IS NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.chat_room_members_list(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_superadmin_remove_from_room(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_superadmin_delete_room(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_leave_room(UUID) TO authenticated;
