-- Chat: push ved reaksjon + bedre forhåndsvisning for posisjon/tråd.

CREATE OR REPLACE FUNCTION public.queue_chat_message_push(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  msg public.chat_messages%ROWTYPE;
  room public.chat_rooms%ROWTYPE;
  sender_name TEXT;
  member RECORD;
  preview TEXT;
  push_title TEXT;
  push_data JSONB;
  n INT;
  sent INT := 0;
BEGIN
  SELECT * INTO msg FROM public.chat_messages WHERE id = p_message_id;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT * INTO room FROM public.chat_rooms WHERE id = msg.room_id;
  SELECT coalesce(nullif(trim(full_name), ''), 'Noen') INTO sender_name
  FROM public.profiles WHERE id = msg.sender_id;

  preview := CASE msg.message_type
    WHEN 'image' THEN sender_name || ' sendte et bilde'
    WHEN 'video' THEN sender_name || ' sendte en video'
    WHEN 'location' THEN sender_name || ' delte en posisjon'
    WHEN 'document' THEN sender_name || ' sendte et dokument'
    WHEN 'voice' THEN sender_name || ' sendte en lydmelding'
    ELSE sender_name || ': ' || left(msg.body, 100)
  END;

  IF msg.thread_root_id IS NOT NULL THEN
    preview := sender_name || ' svarte i en tråd';
  ELSIF msg.reply_to_id IS NOT NULL AND msg.message_type = 'text' THEN
    preview := sender_name || ' svarte: ' || left(msg.body, 80);
  END IF;

  push_title := coalesce(nullif(trim(room.title), ''), 'Ny chat-melding');
  push_data := jsonb_build_object(
    'type', CASE
      WHEN msg.thread_root_id IS NOT NULL THEN 'chat_thread_reply'
      WHEN msg.reply_to_id IS NOT NULL THEN 'chat_reply'
      ELSE 'chat_message'
    END,
    'room_id', msg.room_id::text,
    'message_id', msg.id::text,
    'category', 'chat'
  );

  FOR member IN
    SELECT DISTINCT m.user_id
    FROM public.chat_room_members m
    WHERE m.room_id = msg.room_id
      AND m.user_id IS DISTINCT FROM msg.sender_id
      AND m.left_at IS NULL
  LOOP
    IF EXISTS (
      SELECT 1 FROM public.chat_user_room_prefs p
      WHERE p.room_id = msg.room_id
        AND p.user_id = member.user_id
        AND p.muted_until > now()
    ) THEN
      CONTINUE;
    END IF;

    n := public.queue_push_to_profile_devices(
      room.company_id,
      member.user_id,
      push_title,
      preview,
      'chat',
      'chat_messages',
      msg.id,
      'Chat push',
      push_data
    );
    sent := sent + coalesce(n, 0);
  END LOOP;

  IF room.room_type = 'partner_broadcast' THEN
    FOR member IN
      SELECT DISTINCT ppa.profile_id AS user_id
      FROM public.partner_portal_accounts ppa
      JOIN public.partners pt ON pt.id = ppa.partner_id
      WHERE pt.company_id = room.company_id
        AND coalesce(ppa.is_active, true)
        AND ppa.profile_id IS DISTINCT FROM msg.sender_id
    LOOP
      n := public.queue_push_to_profile_devices(
        room.company_id,
        member.user_id,
        coalesce(nullif(trim(room.title), ''), 'Melding fra MAVI'),
        preview,
        'chat',
        'chat_messages',
        msg.id,
        'Chat broadcast push',
        push_data
      );
      sent := sent + coalesce(n, 0);
    END LOOP;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.chat_toggle_reaction(
  p_message_id UUID,
  p_emoji TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_room UUID;
  v_sender UUID;
  v_company UUID;
  v_reactor TEXT;
  e TEXT := trim(p_emoji);
  added BOOLEAN := false;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Ikke innlogget'; END IF;
  IF e = '' THEN RAISE EXCEPTION 'Ugyldig emoji'; END IF;

  SELECT m.room_id, m.sender_id, r.company_id
  INTO v_room, v_sender, v_company
  FROM public.chat_messages m
  JOIN public.chat_rooms r ON r.id = m.room_id
  WHERE m.id = p_message_id;

  IF v_room IS NULL THEN RAISE EXCEPTION 'Melding ikke funnet'; END IF;
  IF NOT public.chat_user_can_access_room(v_uid, v_room) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.chat_message_reactions
    WHERE message_id = p_message_id AND user_id = v_uid AND emoji = e
  ) THEN
    DELETE FROM public.chat_message_reactions
    WHERE message_id = p_message_id AND user_id = v_uid AND emoji = e;
    RETURN false;
  END IF;

  INSERT INTO public.chat_message_reactions (message_id, user_id, emoji)
  VALUES (p_message_id, v_uid, e);
  added := true;

  IF added AND v_sender IS DISTINCT FROM v_uid THEN
    SELECT coalesce(nullif(trim(full_name), ''), 'Noen') INTO v_reactor
    FROM public.profiles WHERE id = v_uid;

    PERFORM public.queue_push_to_profile_devices(
      v_company,
      v_sender,
      'Ny reaksjon',
      v_reactor || ' reagerte med ' || e,
      'chat',
      'chat_messages',
      p_message_id,
      'Chat reaction push',
      jsonb_build_object(
        'type', 'chat_reaction',
        'room_id', v_room::text,
        'message_id', p_message_id::text,
        'emoji', e,
        'category', 'chat'
      )
    );
  END IF;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.queue_chat_message_push(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.chat_toggle_reaction(UUID, TEXT) TO authenticated;
