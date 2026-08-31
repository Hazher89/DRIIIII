-- Håndhev chat feature flags ved sending (ikke bare skjult UI).

CREATE OR REPLACE FUNCTION public.chat_system_enabled_for_user(p_uid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID;
  v_mavi boolean;
  v_partners boolean;
BEGIN
  v_company := public.chat_user_company_id(p_uid);
  IF v_company IS NULL THEN
    RETURN false;
  END IF;

  SELECT c.chat_enabled_mavi, c.chat_enabled_partners
    INTO v_mavi, v_partners
  FROM public.companies c
  WHERE c.id = v_company;

  IF public.chat_user_is_partner_portal(p_uid) THEN
    RETURN coalesce(v_partners, true);
  END IF;

  RETURN coalesce(v_mavi, true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.chat_system_enabled_for_user(UUID) TO authenticated;

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

  RETURN v_message_id;
END;
$$;
