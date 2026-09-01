-- Avanserte chat-funksjoner (unntatt DriftPro-integrasjon og AI/automatisering).

-- ── Rom-innstillinger ─────────────────────────────────────────────────────────
ALTER TABLE public.chat_rooms
  ADD COLUMN IF NOT EXISTS welcome_message TEXT,
  ADD COLUMN IF NOT EXISTS rules_text TEXT,
  ADD COLUMN IF NOT EXISTS require_member_approval BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS parent_room_id UUID REFERENCES public.chat_rooms(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS pinned_message_id UUID REFERENCES public.chat_messages(id) ON DELETE SET NULL;

-- ── Utvid meldingstyper ─────────────────────────────────────────────────────
ALTER TABLE public.chat_messages DROP CONSTRAINT IF EXISTS chat_messages_body_check;
ALTER TABLE public.chat_messages
  ADD CONSTRAINT chat_messages_body_check
  CHECK (char_length(body) <= 8000);

ALTER TABLE public.chat_messages DROP CONSTRAINT IF EXISTS chat_messages_message_type_check;
ALTER TABLE public.chat_messages
  ADD CONSTRAINT chat_messages_message_type_check
  CHECK (message_type IN ('text', 'system', 'file', 'image', 'video', 'voice', 'document', 'location'));

ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS thread_root_id UUID REFERENCES public.chat_messages(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS translated_body TEXT,
  ADD COLUMN IF NOT EXISTS original_locale TEXT;

CREATE INDEX IF NOT EXISTS idx_chat_messages_expires
  ON public.chat_messages (expires_at) WHERE expires_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_chat_messages_thread
  ON public.chat_messages (thread_root_id) WHERE thread_root_id IS NOT NULL;

-- ── @nevninger ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.chat_message_mentions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL REFERENCES public.chat_messages(id) ON DELETE CASCADE,
  mentioned_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (message_id, mentioned_user_id)
);

CREATE INDEX IF NOT EXISTS idx_chat_mentions_user ON public.chat_message_mentions (mentioned_user_id);

-- ── Levert / lest per melding ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.chat_message_receipts (
  message_id UUID NOT NULL REFERENCES public.chat_messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  delivered_at TIMESTAMPTZ,
  read_at TIMESTAMPTZ,
  PRIMARY KEY (message_id, user_id)
);

-- ── Planlagte meldinger ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.chat_scheduled_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  body TEXT NOT NULL DEFAULT '',
  message_type TEXT NOT NULL DEFAULT 'text',
  reply_to_id UUID REFERENCES public.chat_messages(id) ON DELETE SET NULL,
  attachment JSONB,
  thread_root_id UUID,
  mention_ids UUID[],
  expires_hours INT,
  translated_body TEXT,
  scheduled_for TIMESTAMPTZ NOT NULL,
  sent_message_id UUID REFERENCES public.chat_messages(id) ON DELETE SET NULL,
  cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chat_scheduled_pending
  ON public.chat_scheduled_messages (scheduled_for)
  WHERE sent_message_id IS NULL AND cancelled_at IS NULL;

-- ── Meldingsmaler ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.chat_message_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Rapporter melding ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.chat_message_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL REFERENCES public.chat_messages(id) ON DELETE CASCADE,
  room_id UUID NOT NULL REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
  reporter_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'reviewed', 'dismissed')),
  reviewed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Online-tilstedeværelse ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.chat_user_presence (
  user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  company_id UUID REFERENCES public.companies(id) ON DELETE CASCADE,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  hide_online BOOLEAN NOT NULL DEFAULT false,
  current_room_id UUID REFERENCES public.chat_rooms(id) ON DELETE SET NULL
);

-- ── RLS ───────────────────────────────────────────────────────────────────────
ALTER TABLE public.chat_message_mentions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_message_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_scheduled_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_message_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_message_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_user_presence ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS chat_mentions_select ON public.chat_message_mentions;
CREATE POLICY chat_mentions_select ON public.chat_message_mentions FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.chat_messages m WHERE m.id = message_id AND public.chat_user_can_access_room(auth.uid(), m.room_id)));

DROP POLICY IF EXISTS chat_receipts_select ON public.chat_message_receipts;
CREATE POLICY chat_receipts_select ON public.chat_message_receipts FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.chat_messages m WHERE m.id = message_id AND public.chat_user_can_access_room(auth.uid(), m.room_id)));

DROP POLICY IF EXISTS chat_receipts_own ON public.chat_message_receipts;
CREATE POLICY chat_receipts_own ON public.chat_message_receipts FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS chat_scheduled_own ON public.chat_scheduled_messages;
CREATE POLICY chat_scheduled_own ON public.chat_scheduled_messages FOR ALL TO authenticated
  USING (sender_id = auth.uid()) WITH CHECK (sender_id = auth.uid());

DROP POLICY IF EXISTS chat_templates_read ON public.chat_message_templates;
CREATE POLICY chat_templates_read ON public.chat_message_templates FOR SELECT TO authenticated
  USING (company_id = public.chat_user_company_id(auth.uid()));

DROP POLICY IF EXISTS chat_templates_write ON public.chat_message_templates;
CREATE POLICY chat_templates_write ON public.chat_message_templates FOR ALL TO authenticated
  USING (company_id = public.chat_user_company_id(auth.uid()) AND public.chat_can_moderate(auth.uid()))
  WITH CHECK (company_id = public.chat_user_company_id(auth.uid()) AND public.chat_can_moderate(auth.uid()));

DROP POLICY IF EXISTS chat_reports_insert ON public.chat_message_reports;
CREATE POLICY chat_reports_insert ON public.chat_message_reports FOR INSERT TO authenticated
  WITH CHECK (reporter_id = auth.uid());

DROP POLICY IF EXISTS chat_reports_mod ON public.chat_message_reports;
CREATE POLICY chat_reports_mod ON public.chat_message_reports FOR SELECT TO authenticated
  USING (public.chat_can_moderate(auth.uid()) OR reporter_id = auth.uid());

DROP POLICY IF EXISTS chat_presence_read ON public.chat_user_presence;
CREATE POLICY chat_presence_read ON public.chat_user_presence FOR SELECT TO authenticated
  USING (company_id = public.chat_user_company_id(auth.uid()) OR user_id = auth.uid());

DROP POLICY IF EXISTS chat_presence_own ON public.chat_user_presence;
CREATE POLICY chat_presence_own ON public.chat_user_presence FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- ── Utvid send_chat_message ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.send_chat_message(
  p_room_id UUID,
  p_body TEXT DEFAULT '',
  p_reply_to_id UUID DEFAULT NULL,
  p_message_type TEXT DEFAULT 'text',
  p_attachment JSONB DEFAULT NULL,
  p_mention_ids UUID[] DEFAULT NULL,
  p_thread_root_id UUID DEFAULT NULL,
  p_expires_hours INT DEFAULT NULL,
  p_translated_body TEXT DEFAULT NULL
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
  v_expires TIMESTAMPTZ;
  mid UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Ikke innlogget'; END IF;
  IF NOT public.chat_system_enabled_for_user(v_uid) THEN RAISE EXCEPTION 'Chat er midlertidig avslått'; END IF;
  IF NOT public.chat_user_can_send(v_uid, p_room_id) THEN RAISE EXCEPTION 'Ingen tilgang til å sende i dette rommet'; END IF;
  IF public.chat_user_is_blocked(v_uid, p_room_id) THEN RAISE EXCEPTION 'Du er blokkert fra chat'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.chat_room_members m
    WHERE m.room_id = p_room_id AND m.user_id = v_uid AND m.left_at IS NULL
      AND m.member_role = 'pending'
  ) THEN
    RAISE EXCEPTION 'Venter på godkjenning fra administrator';
  END IF;

  IF v_body = '' AND (p_attachment IS NULL OR p_attachment = '{}'::jsonb) THEN
    RAISE EXCEPTION 'Melding kan ikke være tom';
  END IF;

  IF p_expires_hours IS NOT NULL AND p_expires_hours > 0 THEN
    v_expires := now() + make_interval(hours => p_expires_hours);
  END IF;

  INSERT INTO public.chat_messages (
    room_id, sender_id, body, reply_to_id, message_type,
    thread_root_id, expires_at, translated_body
  )
  VALUES (
    p_room_id, v_uid, v_body, p_reply_to_id, v_type,
    p_thread_root_id, v_expires, nullif(trim(p_translated_body), '')
  )
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
      WHEN 'voice' THEN '🎤 Tale' || CASE WHEN v_body <> '' THEN ': ' || left(v_body, 80) ELSE '' END
      WHEN 'document' THEN '📎 Dokument'
      WHEN 'location' THEN '📍 Posisjon'
      ELSE left(v_body, 120)
    END;
  ELSE
    v_preview := CASE v_type
      WHEN 'voice' THEN '🎤 Tale' || CASE WHEN v_body <> '' THEN ': ' || left(v_body, 80) ELSE '' END
      WHEN 'location' THEN '📍 ' || coalesce(left(v_body, 100), 'Posisjon')
      ELSE left(v_body, 120)
    END;
  END IF;

  UPDATE public.chat_rooms SET last_message_at = now(), last_message_preview = v_preview, updated_at = now() WHERE id = p_room_id;

  INSERT INTO public.chat_read_state (room_id, user_id, last_read_message_id, last_read_at)
  VALUES (p_room_id, v_uid, v_message_id, now())
  ON CONFLICT (room_id, user_id) DO UPDATE SET last_read_message_id = EXCLUDED.last_read_message_id, last_read_at = EXCLUDED.last_read_at;

  INSERT INTO public.chat_message_receipts (message_id, user_id, delivered_at, read_at)
  VALUES (v_message_id, v_uid, now(), now())
  ON CONFLICT DO NOTHING;

  IF p_mention_ids IS NOT NULL THEN
    FOREACH mid IN ARRAY p_mention_ids LOOP
      IF mid IS DISTINCT FROM v_uid AND EXISTS (
        SELECT 1 FROM public.chat_room_members m
        WHERE m.room_id = p_room_id AND m.user_id = mid AND m.left_at IS NULL
      ) THEN
        INSERT INTO public.chat_message_mentions (message_id, mentioned_user_id)
        VALUES (v_message_id, mid) ON CONFLICT DO NOTHING;
        PERFORM public.queue_push_to_profile_devices(
          (SELECT company_id FROM public.chat_rooms WHERE id = p_room_id),
          mid,
          coalesce((SELECT title FROM public.chat_rooms WHERE id = p_room_id), 'Chat'),
          (SELECT coalesce(full_name, 'Noen') FROM public.profiles WHERE id = v_uid) || ' nevnte deg',
          'chat',
          'chat_messages',
          v_message_id,
          'Chat @nevning',
          jsonb_build_object('type', 'chat_message', 'room_id', p_room_id::text, 'message_id', v_message_id::text)
        );
      END IF;
    END LOOP;
  END IF;

  PERFORM public.queue_chat_message_push(v_message_id);
  RETURN v_message_id;
END;
$$;

-- ── Planlagt sending ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_schedule_message(
  p_room_id UUID,
  p_body TEXT,
  p_scheduled_for TIMESTAMPTZ,
  p_message_type TEXT DEFAULT 'text',
  p_attachment JSONB DEFAULT NULL,
  p_reply_to_id UUID DEFAULT NULL,
  p_mention_ids UUID[] DEFAULT NULL,
  p_expires_hours INT DEFAULT NULL,
  p_translated_body TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID; v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Ikke innlogget'; END IF;
  IF NOT public.chat_user_can_send(v_uid, p_room_id) THEN RAISE EXCEPTION 'Ingen tilgang'; END IF;
  IF p_scheduled_for <= now() THEN RAISE EXCEPTION 'Planlagt tid må være i fremtiden'; END IF;

  INSERT INTO public.chat_scheduled_messages (
    room_id, sender_id, body, message_type, reply_to_id, attachment,
    mention_ids, expires_hours, translated_body, scheduled_for
  )
  VALUES (
    p_room_id, v_uid, coalesce(trim(p_body), ''), lower(p_message_type),
    p_reply_to_id, p_attachment, p_mention_ids, p_expires_hours,
    nullif(trim(p_translated_body), ''), p_scheduled_for
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.chat_process_scheduled_messages()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE r RECORD; v_mid UUID; n INT := 0;
BEGIN
  FOR r IN
    SELECT * FROM public.chat_scheduled_messages
    WHERE sent_message_id IS NULL AND cancelled_at IS NULL AND scheduled_for <= now()
    ORDER BY scheduled_for ASC LIMIT 50
  LOOP
  BEGIN
    v_mid := public.send_chat_message(
      r.room_id, r.body, r.reply_to_id, r.message_type, r.attachment,
      r.mention_ids, r.thread_root_id, r.expires_hours, r.translated_body
    );
    UPDATE public.chat_scheduled_messages SET sent_message_id = v_mid WHERE id = r.id;
    n := n + 1;
  EXCEPTION WHEN OTHERS THEN
    UPDATE public.chat_scheduled_messages SET cancelled_at = now() WHERE id = r.id;
  END;
  END LOOP;
  RETURN n;
END;
$$;

-- ── Fest melding ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_pin_room_message(p_room_id UUID, p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.chat_can_moderate(auth.uid()) AND NOT EXISTS (
    SELECT 1 FROM public.chat_room_members m
    WHERE m.room_id = p_room_id AND m.user_id = auth.uid()
      AND m.member_role IN ('owner', 'admin') AND m.left_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;
  UPDATE public.chat_rooms SET pinned_message_id = p_message_id, updated_at = now() WHERE id = p_room_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.chat_unpin_room_message(p_room_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.chat_rooms SET pinned_message_id = NULL, updated_at = now() WHERE id = p_room_id;
END;
$$;

-- ── Rapporter ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_report_message(p_message_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_room UUID; v_id UUID;
BEGIN
  SELECT room_id INTO v_room FROM public.chat_messages WHERE id = p_message_id;
  IF v_room IS NULL THEN RAISE EXCEPTION 'Melding ikke funnet'; END IF;
  INSERT INTO public.chat_message_reports (message_id, room_id, reporter_id, reason)
  VALUES (p_message_id, v_room, auth.uid(), nullif(trim(p_reason), ''))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ── Godkjenn medlem ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_approve_room_member(p_room_id UUID, p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.chat_can_moderate(auth.uid()) AND NOT EXISTS (
    SELECT 1 FROM public.chat_room_members m
    WHERE m.room_id = p_room_id AND m.user_id = auth.uid()
      AND m.member_role IN ('owner', 'admin') AND m.left_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;
  UPDATE public.chat_room_members SET member_role = 'member'
  WHERE room_id = p_room_id AND user_id = p_user_id AND member_role = 'pending';
END;
$$;

-- ── Tilstedeværelse ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_heartbeat(p_room_id UUID DEFAULT NULL, p_hide_online BOOLEAN DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid UUID := auth.uid(); v_co UUID;
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;
  v_co := public.chat_user_company_id(v_uid);
  INSERT INTO public.chat_user_presence (user_id, company_id, last_seen_at, hide_online, current_room_id)
  VALUES (v_uid, v_co, now(), coalesce(p_hide_online, false), p_room_id)
  ON CONFLICT (user_id) DO UPDATE SET
    last_seen_at = now(),
    company_id = EXCLUDED.company_id,
    hide_online = CASE WHEN p_hide_online IS NULL THEN public.chat_user_presence.hide_online ELSE p_hide_online END,
    current_room_id = COALESCE(p_room_id, public.chat_user_presence.current_room_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.chat_room_online_users(p_room_id UUID)
RETURNS TABLE(user_id UUID, full_name TEXT, is_online BOOLEAN)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, coalesce(nullif(trim(p.full_name), ''), 'Bruker'),
    (pr.last_seen_at > now() - interval '2 minutes' AND NOT pr.hide_online)
  FROM public.chat_room_members m
  JOIN public.profiles p ON p.id = m.user_id
  LEFT JOIN public.chat_user_presence pr ON pr.user_id = p.id
  WHERE m.room_id = p_room_id AND m.left_at IS NULL
    AND public.chat_user_can_access_room(auth.uid(), p_room_id);
$$;

-- ── Levert / lest ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_mark_delivered(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.chat_message_receipts (message_id, user_id, delivered_at)
  VALUES (p_message_id, auth.uid(), now())
  ON CONFLICT (message_id, user_id) DO UPDATE
    SET delivered_at = COALESCE(public.chat_message_receipts.delivered_at, EXCLUDED.delivered_at);
END;
$$;

-- ── Undergruppe ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_create_subgroup(
  p_parent_room_id UUID,
  p_title TEXT,
  p_member_ids UUID[] DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid UUID := auth.uid(); v_parent public.chat_rooms%ROWTYPE; v_room UUID; mid UUID;
BEGIN
  SELECT * INTO v_parent FROM public.chat_rooms WHERE id = p_parent_room_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Foreldre-rom finnes ikke'; END IF;
  IF NOT public.chat_user_can_access_room(v_uid, p_parent_room_id) THEN RAISE EXCEPTION 'Ingen tilgang'; END IF;

  INSERT INTO public.chat_rooms (company_id, room_type, title, created_by, parent_room_id)
  VALUES (v_parent.company_id, v_parent.room_type, trim(p_title), v_uid, p_parent_room_id)
  RETURNING id INTO v_room;

  INSERT INTO public.chat_room_members (room_id, user_id, member_role)
  SELECT v_room, m.user_id, m.member_role
  FROM public.chat_room_members m
  WHERE m.room_id = p_parent_room_id AND m.left_at IS NULL
  ON CONFLICT DO NOTHING;

  RETURN v_room;
END;
$$;

-- ── Velkomstmelding ved nytt medlem ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_on_member_joined()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_welcome TEXT; v_room public.chat_rooms%ROWTYPE;
BEGIN
  IF NEW.left_at IS NOT NULL THEN RETURN NEW; END IF;
  SELECT * INTO v_room FROM public.chat_rooms WHERE id = NEW.room_id;
  v_welcome := nullif(trim(v_room.welcome_message), '');
  IF v_welcome IS NOT NULL THEN
    INSERT INTO public.chat_messages (room_id, sender_id, body, message_type)
    VALUES (NEW.room_id, coalesce(v_room.created_by, NEW.user_id), v_welcome, 'system');
  END IF;
  IF v_room.require_member_approval AND NEW.member_role IS NULL THEN
    NEW.member_role := 'pending';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_chat_member_welcome ON public.chat_room_members;
CREATE TRIGGER trg_chat_member_welcome
  BEFORE INSERT ON public.chat_room_members
  FOR EACH ROW EXECUTE FUNCTION public.chat_on_member_joined();

-- ── Slett utløpte meldinger ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_purge_expired_messages()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE n INT;
BEGIN
  UPDATE public.chat_messages
  SET deleted_at = now(), body = '[Utløpt]', moderation_state = 'hidden'
  WHERE expires_at IS NOT NULL AND expires_at <= now() AND deleted_at IS NULL;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

-- ── Statistikk ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chat_superadmin_stats(p_days INT DEFAULT 30)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_co UUID; v_uid UUID := auth.uid();
BEGIN
  IF NOT public.chat_can_moderate(v_uid) THEN RAISE EXCEPTION 'Kun moderator'; END IF;
  v_co := public.chat_user_company_id(v_uid);
  RETURN jsonb_build_object(
    'total_messages', (SELECT count(*) FROM public.chat_messages m JOIN public.chat_rooms r ON r.id = m.room_id WHERE r.company_id = v_co AND m.created_at > now() - make_interval(days => p_days)),
    'active_rooms', (SELECT count(DISTINCT m.room_id) FROM public.chat_messages m JOIN public.chat_rooms r ON r.id = m.room_id WHERE r.company_id = v_co AND m.created_at > now() - make_interval(days => p_days)),
    'open_reports', (SELECT count(*) FROM public.chat_message_reports rep JOIN public.chat_rooms r ON r.id = rep.room_id WHERE r.company_id = v_co AND rep.status = 'open'),
    'pending_members', (SELECT count(*) FROM public.chat_room_members m JOIN public.chat_rooms r ON r.id = m.room_id WHERE r.company_id = v_co AND m.member_role = 'pending' AND m.left_at IS NULL)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.chat_schedule_message TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_process_scheduled_messages() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.chat_pin_room_message(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_unpin_room_message(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_report_message(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_approve_room_member(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_heartbeat(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_room_online_users(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_mark_delivered(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_create_subgroup(UUID, TEXT, UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_superadmin_stats(INT) TO authenticated;
