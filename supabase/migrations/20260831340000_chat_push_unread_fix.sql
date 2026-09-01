-- Gjenopprett chat push (ble fjernet i chat_flags_enforce_send) og forbedre enhetsdekning.

CREATE OR REPLACE FUNCTION public.send_chat_message(
  p_room_id UUID,
  p_body TEXT DEFAULT '',
  p_reply_to_id UUID DEFAULT NULL,
  p_message_type TEXT DEFAULT 'text',
  p_attachment JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_message_id UUID;
  v_preview TEXT;
  v_body TEXT := coalesce(trim(p_body), '');
  v_type TEXT := lower(coalesce(p_message_type, 'text'));
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Ikke innlogget'; END IF;

  IF NOT public.chat_system_enabled_for_user(v_uid) THEN
    RAISE EXCEPTION 'Chat er midlertidig avslått';
  END IF;

  IF NOT public.chat_user_can_send(v_uid, p_room_id) THEN
    RAISE EXCEPTION 'Ingen tilgang til å sende i dette rommet';
  END IF;
  IF public.chat_user_is_blocked(v_uid, p_room_id) THEN
    RAISE EXCEPTION 'Du er blokkert fra chat';
  END IF;

  IF v_body = '' AND (p_attachment IS NULL OR p_attachment = '{}'::jsonb) THEN
    RAISE EXCEPTION 'Melding kan ikke være tom';
  END IF;

  IF p_reply_to_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.chat_messages
      WHERE id = p_reply_to_id AND room_id = p_room_id
    ) THEN
      RAISE EXCEPTION 'Ugyldig svar-referanse';
    END IF;
  END IF;

  INSERT INTO public.chat_messages (room_id, sender_id, body, reply_to_id, message_type)
  VALUES (p_room_id, v_uid, v_body, p_reply_to_id, v_type)
  RETURNING id INTO v_message_id;

  IF p_attachment IS NOT NULL AND p_attachment <> '{}'::jsonb THEN
    INSERT INTO public.chat_message_attachments (
      message_id, storage_path, mime_type, file_name, byte_size, width, height, duration_ms
    )
    VALUES (
      v_message_id,
      p_attachment->>'storage_path',
      coalesce(p_attachment->>'mime_type', 'application/octet-stream'),
      p_attachment->>'file_name',
      nullif(p_attachment->>'byte_size', '')::bigint,
      nullif(p_attachment->>'width', '')::int,
      nullif(p_attachment->>'height', '')::int,
      nullif(p_attachment->>'duration_ms', '')::int
    );
    v_preview := CASE v_type
      WHEN 'image' THEN '📷 Bilde' || CASE WHEN v_body <> '' THEN ': ' || left(v_body, 80) ELSE '' END
      WHEN 'video' THEN '🎬 Video' || CASE WHEN v_body <> '' THEN ': ' || left(v_body, 80) ELSE '' END
      ELSE left(v_body, 120)
    END;
  ELSE
    v_preview := left(v_body, 120);
  END IF;

  UPDATE public.chat_rooms
  SET last_message_at = now(),
      last_message_preview = v_preview,
      updated_at = now()
  WHERE id = p_room_id;

  INSERT INTO public.chat_read_state (room_id, user_id, last_read_message_id, last_read_at)
  VALUES (p_room_id, v_uid, v_message_id, now())
  ON CONFLICT (room_id, user_id) DO UPDATE
    SET last_read_message_id = EXCLUDED.last_read_message_id,
        last_read_at = EXCLUDED.last_read_at;

  PERFORM public.queue_chat_message_push(v_message_id);

  RETURN v_message_id;
END;
$$;

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
    ELSE sender_name || ': ' || left(msg.body, 100)
  END;

  push_title := coalesce(nullif(trim(room.title), ''), 'Ny chat-melding');
  push_data := jsonb_build_object(
    'type', 'chat_message',
    'room_id', msg.room_id::text,
    'message_id', msg.id::text
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

-- Direkte push til alle enheter (uten firmavalg-blokkering for chat).
CREATE OR REPLACE FUNCTION public.queue_push_to_profile_devices(
  p_company_id UUID,
  p_profile_id UUID,
  p_title TEXT,
  p_body TEXT,
  p_category TEXT,
  p_reference_type TEXT,
  p_reference_id UUID,
  p_description TEXT,
  p_data JSONB DEFAULT '{}'::jsonb
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d RECORD;
  n INT := 0;
  sent TEXT[] := ARRAY[]::TEXT[];
  legacy_tok TEXT;
BEGIN
  IF p_profile_id IS NULL THEN RETURN 0; END IF;

  FOR d IN
    SELECT DISTINCT ON (upd.fcm_token)
      upd.fcm_token
    FROM public.user_push_devices upd
    WHERE upd.profile_id = p_profile_id
      AND upd.is_active = true
      AND nullif(trim(upd.fcm_token), '') IS NOT NULL
    ORDER BY upd.fcm_token, upd.last_seen_at DESC
  LOOP
    IF NOT (d.fcm_token = ANY (sent)) THEN
      INSERT INTO public.push_outbox (
        company_id, profile_id, fcm_token, title, body, data,
        category, reference_type, reference_id, description
      )
      VALUES (
        p_company_id,
        p_profile_id,
        d.fcm_token,
        left(trim(p_title), 120),
        left(trim(p_body), 500),
        p_data,
        p_category,
        p_reference_type,
        p_reference_id,
        p_description
      );
      n := n + 1;
      sent := array_append(sent, d.fcm_token);
    END IF;
  END LOOP;

  IF n = 0 THEN
    SELECT pr.fcm_token INTO legacy_tok
    FROM public.profiles pr
    WHERE pr.id = p_profile_id
      AND nullif(trim(pr.fcm_token), '') IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.user_push_devices upd
        WHERE upd.profile_id = p_profile_id AND upd.is_active = true
      );

    IF legacy_tok IS NOT NULL AND NOT (legacy_tok = ANY (sent)) THEN
      INSERT INTO public.push_outbox (
        company_id, profile_id, fcm_token, title, body, data,
        category, reference_type, reference_id, description
      )
      VALUES (
        p_company_id,
        p_profile_id,
        legacy_tok,
        left(trim(p_title), 120),
        left(trim(p_body), 500),
        p_data,
        p_category,
        p_reference_type,
        p_reference_id,
        p_description
      );
      n := 1;
    END IF;
  END IF;

  RETURN n;
END;
$$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_rooms;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.queue_push_to_profile_devices TO authenticated, service_role;
