-- Avansert chat v2: grupper, arkiv, vedlegg (bilde/video), push, swipe-svar-støtte.

-- ── Utvid romtyper ────────────────────────────────────────────────────────────
ALTER TYPE public.chat_room_type ADD VALUE IF NOT EXISTS 'partner_group';
ALTER TYPE public.chat_room_type ADD VALUE IF NOT EXISTS 'mavi_group';

-- ── Per-bruker rom-prefs (arkiv, pin, mute) ───────────────────────────────────
CREATE TABLE IF NOT EXISTS public.chat_user_room_prefs (
  room_id UUID NOT NULL REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  archived_at TIMESTAMPTZ,
  pinned_at TIMESTAMPTZ,
  muted_until TIMESTAMPTZ,
  draft_text TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (room_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_chat_user_room_prefs_archived
  ON public.chat_user_room_prefs (user_id, archived_at)
  WHERE archived_at IS NOT NULL;

-- ── Vedlegg ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.chat_message_attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL REFERENCES public.chat_messages(id) ON DELETE CASCADE,
  storage_path TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  file_name TEXT,
  byte_size BIGINT,
  width INT,
  height INT,
  duration_ms INT,
  thumbnail_path TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chat_attachments_message
  ON public.chat_message_attachments (message_id);

-- Tillat tom body når vedlegg finnes
ALTER TABLE public.chat_messages DROP CONSTRAINT IF EXISTS chat_messages_body_check;
ALTER TABLE public.chat_messages
  ADD CONSTRAINT chat_messages_body_check
  CHECK (char_length(body) <= 8000);

ALTER TABLE public.chat_messages DROP CONSTRAINT IF EXISTS chat_messages_message_type_check;
ALTER TABLE public.chat_messages
  ADD CONSTRAINT chat_messages_message_type_check
  CHECK (message_type IN ('text', 'system', 'file', 'image', 'video'));

-- ── Storage bucket for chat-media ─────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'chat-media',
  'chat-media',
  false,
  52428800,
  ARRAY[
    'image/jpeg', 'image/png', 'image/webp', 'image/gif',
    'video/mp4', 'video/quicktime', 'video/webm'
  ]::text[]
)
ON CONFLICT (id) DO UPDATE SET
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS chat_media_insert ON storage.objects;
CREATE POLICY chat_media_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'chat-media'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS chat_media_select ON storage.objects;
CREATE POLICY chat_media_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'chat-media'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR public.chat_can_moderate(auth.uid())
    )
  );

-- ── Oppdater tilgangsfunksjon for partner_group ───────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_user_can_access_room(p_uid UUID, p_room_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r public.chat_rooms%ROWTYPE;
BEGIN
  IF p_uid IS NULL OR p_room_id IS NULL THEN RETURN FALSE; END IF;
  IF public.chat_can_moderate(p_uid) THEN RETURN TRUE; END IF;
  IF public.chat_user_is_blocked(p_uid, p_room_id) THEN RETURN FALSE; END IF;

  SELECT * INTO r FROM public.chat_rooms WHERE id = p_room_id;
  IF NOT FOUND OR r.is_archived THEN RETURN FALSE; END IF;
  IF public.chat_user_company_id(p_uid) IS DISTINCT FROM r.company_id THEN RETURN FALSE; END IF;

  CASE r.room_type
    WHEN 'mavi_internal', 'mavi_group' THEN
      RETURN public.chat_user_is_mavi_employee(p_uid)
        AND EXISTS (
          SELECT 1 FROM public.chat_room_members m
          WHERE m.room_id = p_room_id AND m.user_id = p_uid AND m.left_at IS NULL
        );
    WHEN 'partner_broadcast' THEN
      RETURN public.chat_user_is_partner_portal(p_uid)
        OR public.chat_user_is_mavi_employee(p_uid);
    WHEN 'partner_private', 'partner_group' THEN
      IF public.chat_user_is_mavi_employee(p_uid) THEN RETURN FALSE; END IF;
      RETURN public.chat_user_is_partner_portal(p_uid)
        AND EXISTS (
          SELECT 1 FROM public.chat_room_members m
          WHERE m.room_id = p_room_id AND m.user_id = p_uid AND m.left_at IS NULL
        );
    WHEN 'mavi_partner_direct' THEN
      RETURN EXISTS (
        SELECT 1 FROM public.chat_room_members m
        WHERE m.room_id = p_room_id AND m.user_id = p_uid AND m.left_at IS NULL
      );
    ELSE RETURN FALSE;
  END CASE;
END;
$$;

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

-- ── Partner-gruppe (MAVI-blind) ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_partner_group_chat(
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
  v_company_id UUID;
  v_room_id UUID;
  mid UUID;
  v_count INT := 0;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Ikke innlogget'; END IF;
  IF NOT public.chat_user_is_partner_portal(v_uid) THEN
    RAISE EXCEPTION 'Kun partnere kan opprette partner-grupper';
  END IF;
  IF coalesce(trim(p_title), '') = '' THEN
    RAISE EXCEPTION 'Gruppen må ha et navn';
  END IF;

  v_company_id := public.chat_user_company_id(v_uid);

  INSERT INTO public.chat_rooms (company_id, room_type, title, created_by)
  VALUES (v_company_id, 'partner_group', trim(p_title), v_uid)
  RETURNING id INTO v_room_id;

  INSERT INTO public.chat_room_members (room_id, user_id, partner_id, member_role)
  VALUES (v_room_id, v_uid, public.chat_user_partner_id(v_uid), 'owner')
  ON CONFLICT DO NOTHING;

  v_count := 1;

  FOREACH mid IN ARRAY coalesce(p_member_ids, ARRAY[]::UUID[])
  LOOP
    IF mid IS DISTINCT FROM v_uid
       AND public.chat_user_is_partner_portal(mid)
       AND public.chat_user_company_id(mid) = v_company_id
       AND NOT public.chat_user_is_blocked(mid) THEN
      INSERT INTO public.chat_room_members (room_id, user_id, partner_id, member_role)
      VALUES (v_room_id, mid, public.chat_user_partner_id(mid), 'member')
      ON CONFLICT DO NOTHING;
      v_count := v_count + 1;
    END IF;
  END LOOP;

  IF v_count < 2 THEN
    RAISE EXCEPTION 'Gruppe må ha minst 2 medlemmer';
  END IF;

  RETURN v_room_id;
END;
$$;

-- ── MAVI-gruppe ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_mavi_group_chat(
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
  v_company_id UUID;
  v_room_id UUID;
  mid UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Ikke innlogget'; END IF;
  IF NOT public.chat_user_is_mavi_employee(v_uid) THEN RAISE EXCEPTION 'Kun MAVI-ansatte'; END IF;
  IF NOT public.profile_has_access(v_uid, 'partners.chat.internal', 'create') THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  v_company_id := public.chat_user_company_id(v_uid);

  INSERT INTO public.chat_rooms (company_id, room_type, title, created_by)
  VALUES (v_company_id, 'mavi_group', nullif(trim(p_title), ''), v_uid)
  RETURNING id INTO v_room_id;

  INSERT INTO public.chat_room_members (room_id, user_id, member_role)
  VALUES (v_room_id, v_uid, 'owner') ON CONFLICT DO NOTHING;

  FOREACH mid IN ARRAY coalesce(p_member_ids, ARRAY[]::UUID[])
  LOOP
    IF mid IS DISTINCT FROM v_uid
       AND public.chat_user_is_mavi_employee(mid)
       AND public.chat_user_company_id(mid) = v_company_id THEN
      INSERT INTO public.chat_room_members (room_id, user_id, member_role)
      VALUES (v_room_id, mid, 'member') ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;

  RETURN v_room_id;
END;
$$;

-- ── Arkiv ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_set_room_archived(p_room_id UUID, p_archived BOOLEAN)
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

  INSERT INTO public.chat_user_room_prefs (room_id, user_id, archived_at, updated_at)
  VALUES (p_room_id, v_uid, CASE WHEN p_archived THEN now() ELSE NULL END, now())
  ON CONFLICT (room_id, user_id) DO UPDATE
    SET archived_at = CASE WHEN p_archived THEN now() ELSE NULL END,
        updated_at = now();
END;
$$;

-- ── Utvid send melding (tekst + vedlegg + svar) ───────────────────────────────
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

-- ── Push ved ny melding ───────────────────────────────────────────────────────
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
BEGIN
  SELECT * INTO msg FROM public.chat_messages WHERE id = p_message_id;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT * INTO room FROM public.chat_rooms WHERE id = msg.room_id;
  SELECT coalesce(full_name, 'Ny melding') INTO sender_name
  FROM public.profiles WHERE id = msg.sender_id;

  preview := CASE msg.message_type
    WHEN 'image' THEN coalesce(sender_name, 'Noen') || ' sendte et bilde'
    WHEN 'video' THEN coalesce(sender_name, 'Noen') || ' sendte en video'
    ELSE coalesce(sender_name, 'Noen') || ': ' || left(msg.body, 100)
  END;

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

    INSERT INTO public.push_outbox (
      company_id, profile_id, fcm_token, title, body, data,
      category, reference_type, reference_id, description
    )
    SELECT
      room.company_id,
      member.user_id,
      upd.fcm_token,
      coalesce(room.title, 'Ny chat-melding'),
      preview,
      jsonb_build_object(
        'type', 'chat_message',
        'room_id', msg.room_id::text,
        'message_id', msg.id::text
      ),
      'chat',
      'chat_messages',
      msg.id,
      'Chat push'
    FROM public.user_push_devices upd
    WHERE upd.profile_id = member.user_id
      AND upd.is_active = true
      AND upd.fcm_token IS NOT NULL
      AND trim(upd.fcm_token) <> '';
  END LOOP;

  -- Broadcast: alle partnere uten eksplisitt medlemskap
  IF room.room_type = 'partner_broadcast' THEN
    INSERT INTO public.push_outbox (
      company_id, profile_id, fcm_token, title, body, data,
      category, reference_type, reference_id, description
    )
    SELECT
      room.company_id,
      ppa.profile_id,
      upd.fcm_token,
      coalesce(room.title, 'Melding fra MAVI'),
      preview,
      jsonb_build_object(
        'type', 'chat_message',
        'room_id', msg.room_id::text,
        'message_id', msg.id::text
      ),
      'chat',
      'chat_messages',
      msg.id,
      'Chat broadcast push'
    FROM public.partner_portal_accounts ppa
    JOIN public.partners pt ON pt.id = ppa.partner_id
    JOIN public.user_push_devices upd ON upd.profile_id = ppa.profile_id AND upd.is_active
    WHERE pt.company_id = room.company_id
      AND coalesce(ppa.is_active, true)
      AND ppa.profile_id IS DISTINCT FROM msg.sender_id
      AND upd.fcm_token IS NOT NULL
      AND trim(upd.fcm_token) <> '';
  END IF;
END;
$$;

-- ── RLS vedlegg ───────────────────────────────────────────────────────────────
ALTER TABLE public.chat_message_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_user_room_prefs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS chat_attachments_select ON public.chat_message_attachments;
CREATE POLICY chat_attachments_select ON public.chat_message_attachments
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.chat_messages m
      WHERE m.id = message_id
        AND public.chat_user_can_access_room(auth.uid(), m.room_id)
    )
  );

DROP POLICY IF EXISTS chat_user_room_prefs_own ON public.chat_user_room_prefs;
CREATE POLICY chat_user_room_prefs_own ON public.chat_user_room_prefs
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

GRANT EXECUTE ON FUNCTION public.create_partner_group_chat(UUID[], TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_mavi_group_chat(UUID[], TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_set_room_archived(UUID, BOOLEAN) TO authenticated;
