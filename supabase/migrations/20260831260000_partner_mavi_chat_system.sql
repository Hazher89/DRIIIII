-- Partner ↔ MAVI chat — GDPR-vennlig, kanalbasert med RLS.
-- Kanaltyper:
--   mavi_internal      — kun MAVI-ansatte (MAVI ser aldri partner-private)
--   partner_broadcast  — MAVI med tilgang → alle partnere i bedriften leser
--   partner_private    — 1:1 mellom partnere, MAVI-blind
--   mavi_partner_direct — MAVI med tilgang ↔ én partner-bedrift

CREATE TYPE public.chat_room_type AS ENUM (
  'mavi_internal',
  'partner_broadcast',
  'partner_private',
  'mavi_partner_direct'
);

CREATE TYPE public.chat_member_role AS ENUM (
  'owner',
  'member',
  'readonly'
);

CREATE TABLE IF NOT EXISTS public.chat_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  room_type public.chat_room_type NOT NULL,
  title TEXT,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  partner_id UUID REFERENCES public.partners(id) ON DELETE CASCADE,
  is_archived BOOLEAN NOT NULL DEFAULT FALSE,
  last_message_at TIMESTAMPTZ,
  last_message_preview TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chat_rooms_partner_direct_requires_partner
    CHECK (
      room_type <> 'mavi_partner_direct'
      OR partner_id IS NOT NULL
    ),
  CONSTRAINT chat_rooms_private_no_partner
    CHECK (
      room_type <> 'partner_private'
      OR partner_id IS NULL
    )
);

CREATE INDEX IF NOT EXISTS idx_chat_rooms_company_type
  ON public.chat_rooms (company_id, room_type, last_message_at DESC NULLS LAST);

CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_rooms_company_broadcast
  ON public.chat_rooms (company_id)
  WHERE room_type = 'partner_broadcast';

CREATE TABLE IF NOT EXISTS public.chat_room_members (
  room_id UUID NOT NULL REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  partner_id UUID REFERENCES public.partners(id) ON DELETE SET NULL,
  member_role public.chat_member_role NOT NULL DEFAULT 'member',
  muted_until TIMESTAMPTZ,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  left_at TIMESTAMPTZ,
  PRIMARY KEY (room_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_chat_room_members_user
  ON public.chat_room_members (user_id)
  WHERE left_at IS NULL;

CREATE TABLE IF NOT EXISTS public.chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID NOT NULL REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK (char_length(trim(body)) > 0 AND char_length(body) <= 8000),
  message_type TEXT NOT NULL DEFAULT 'text' CHECK (message_type IN ('text', 'system', 'file')),
  reply_to_id UUID REFERENCES public.chat_messages(id) ON DELETE SET NULL,
  is_edited BOOLEAN NOT NULL DEFAULT FALSE,
  deleted_at TIMESTAMPTZ,
  moderation_state TEXT NOT NULL DEFAULT 'active'
    CHECK (moderation_state IN ('active', 'blocked', 'hidden')),
  blocked_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  blocked_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_room_created
  ON public.chat_messages (room_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.chat_read_state (
  room_id UUID NOT NULL REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  last_read_message_id UUID REFERENCES public.chat_messages(id) ON DELETE SET NULL,
  last_read_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (room_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.chat_user_blocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  blocked_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  blocked_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  scope TEXT NOT NULL DEFAULT 'global' CHECK (scope IN ('global', 'room')),
  room_id UUID REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
  reason TEXT,
  blocked_until TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (blocked_user_id, scope, room_id)
);

CREATE TABLE IF NOT EXISTS public.chat_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  room_id UUID REFERENCES public.chat_rooms(id) ON DELETE SET NULL,
  message_id UUID REFERENCES public.chat_messages(id) ON DELETE SET NULL,
  target_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  meta JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Helpers ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.chat_user_is_partner_portal(p_uid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.partner_portal_accounts ppa
    WHERE ppa.profile_id = p_uid
      AND coalesce(ppa.is_active, TRUE)
  );
$$;

CREATE OR REPLACE FUNCTION public.chat_user_is_mavi_employee(p_uid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = p_uid
      AND coalesce(p.is_active, TRUE)
      AND p.company_id IS NOT NULL
      AND NOT public.chat_user_is_partner_portal(p_uid)
  );
$$;

CREATE OR REPLACE FUNCTION public.chat_user_company_id(p_uid UUID)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(
    (SELECT p.company_id FROM public.profiles p WHERE p.id = p_uid),
    (
      SELECT pt.company_id
      FROM public.partner_portal_accounts ppa
      JOIN public.partners pt ON pt.id = ppa.partner_id
      WHERE ppa.profile_id = p_uid
        AND coalesce(ppa.is_active, TRUE)
      LIMIT 1
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.chat_user_partner_id(p_uid UUID)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(
    (
      SELECT ppa.partner_id
      FROM public.partner_portal_accounts ppa
      WHERE ppa.profile_id = p_uid
        AND coalesce(ppa.is_active, TRUE)
      LIMIT 1
    ),
    (SELECT p.partner_id FROM public.profiles p WHERE p.id = p_uid)
  );
$$;

CREATE OR REPLACE FUNCTION public.chat_can_moderate(p_uid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.get_user_role() = 'superadmin'::public.user_role
    OR public.profile_has_access(p_uid, 'partners.chat.moderate', 'view');
$$;

CREATE OR REPLACE FUNCTION public.chat_can_send_broadcast(p_uid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.get_user_role() IN ('superadmin'::public.user_role, 'admin'::public.user_role)
    OR public.profile_has_access(p_uid, 'partners.chat.broadcast', 'create');
$$;

CREATE OR REPLACE FUNCTION public.chat_can_send_direct_to_partner(p_uid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.get_user_role() IN ('superadmin'::public.user_role, 'admin'::public.user_role)
    OR public.profile_has_access(p_uid, 'partners.chat.direct', 'create');
$$;

CREATE OR REPLACE FUNCTION public.chat_user_is_blocked(
  p_user_id UUID,
  p_room_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.chat_user_blocks b
    WHERE b.blocked_user_id = p_user_id
      AND (b.blocked_until IS NULL OR b.blocked_until > now())
      AND (
        b.scope = 'global'
        OR (b.scope = 'room' AND b.room_id = p_room_id)
      )
  );
$$;

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
  IF p_uid IS NULL OR p_room_id IS NULL THEN
    RETURN FALSE;
  END IF;

  IF public.chat_can_moderate(p_uid) THEN
    RETURN TRUE;
  END IF;

  IF public.chat_user_is_blocked(p_uid, p_room_id) THEN
    RETURN FALSE;
  END IF;

  SELECT * INTO r FROM public.chat_rooms WHERE id = p_room_id;
  IF NOT FOUND OR r.is_archived THEN
    RETURN FALSE;
  END IF;

  IF public.chat_user_company_id(p_uid) IS DISTINCT FROM r.company_id THEN
    RETURN FALSE;
  END IF;

  CASE r.room_type
    WHEN 'mavi_internal' THEN
      RETURN public.chat_user_is_mavi_employee(p_uid)
        AND EXISTS (
          SELECT 1 FROM public.chat_room_members m
          WHERE m.room_id = p_room_id
            AND m.user_id = p_uid
            AND m.left_at IS NULL
        );

    WHEN 'partner_broadcast' THEN
      RETURN public.chat_user_is_partner_portal(p_uid)
        OR public.chat_user_is_mavi_employee(p_uid);

    WHEN 'partner_private' THEN
      -- MAVI skal ALDRI se partner-private (GDPR / tillit)
      IF public.chat_user_is_mavi_employee(p_uid) THEN
        RETURN FALSE;
      END IF;
      RETURN public.chat_user_is_partner_portal(p_uid)
        AND EXISTS (
          SELECT 1 FROM public.chat_room_members m
          WHERE m.room_id = p_room_id
            AND m.user_id = p_uid
            AND m.left_at IS NULL
        );

    WHEN 'mavi_partner_direct' THEN
      RETURN EXISTS (
        SELECT 1 FROM public.chat_room_members m
        WHERE m.room_id = p_room_id
          AND m.user_id = p_uid
          AND m.left_at IS NULL
      );

    ELSE
      RETURN FALSE;
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
  IF NOT public.chat_user_can_access_room(p_uid, p_room_id) THEN
    RETURN FALSE;
  END IF;

  IF public.chat_user_is_blocked(p_uid, p_room_id) THEN
    RETURN FALSE;
  END IF;

  SELECT * INTO r FROM public.chat_rooms WHERE id = p_room_id;
  SELECT * INTO mem
  FROM public.chat_room_members
  WHERE room_id = p_room_id AND user_id = p_uid AND left_at IS NULL;

  CASE r.room_type
    WHEN 'mavi_internal' THEN
      RETURN public.chat_user_is_mavi_employee(p_uid)
        AND (mem.member_role IS NULL OR mem.member_role <> 'readonly');

    WHEN 'partner_broadcast' THEN
      RETURN public.chat_can_send_broadcast(p_uid);

    WHEN 'partner_private' THEN
      RETURN public.chat_user_is_partner_portal(p_uid)
        AND (mem.member_role IS NULL OR mem.member_role <> 'readonly');

    WHEN 'mavi_partner_direct' THEN
      IF public.chat_user_is_partner_portal(p_uid) THEN
        RETURN mem.member_role IS NULL OR mem.member_role <> 'readonly';
      END IF;
      RETURN public.chat_can_send_direct_to_partner(p_uid);

    ELSE
      RETURN FALSE;
  END CASE;
END;
$$;

-- ── Ensure broadcast room per company ───────────────────────────────────────

CREATE OR REPLACE FUNCTION public.ensure_partner_broadcast_room(p_company_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_id UUID;
BEGIN
  SELECT id INTO v_room_id
  FROM public.chat_rooms
  WHERE company_id = p_company_id
    AND room_type = 'partner_broadcast'
  LIMIT 1;

  IF v_room_id IS NOT NULL THEN
    RETURN v_room_id;
  END IF;

  INSERT INTO public.chat_rooms (company_id, room_type, title)
  VALUES (p_company_id, 'partner_broadcast', 'Meldinger fra MAVI')
  RETURNING id INTO v_room_id;

  RETURN v_room_id;
END;
$$;

-- Auto-join nye partner-portal brukere til broadcast
CREATE OR REPLACE FUNCTION public.trg_chat_join_partner_broadcast()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_room_id UUID;
BEGIN
  IF coalesce(NEW.is_active, TRUE) IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  SELECT pt.company_id INTO v_company_id
  FROM public.partners pt
  WHERE pt.id = NEW.partner_id;

  IF v_company_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_room_id := public.ensure_partner_broadcast_room(v_company_id);

  INSERT INTO public.chat_room_members (room_id, user_id, partner_id, member_role)
  VALUES (v_room_id, NEW.profile_id, NEW.partner_id, 'readonly')
  ON CONFLICT (room_id, user_id) DO UPDATE
    SET left_at = NULL,
        partner_id = EXCLUDED.partner_id,
        member_role = 'readonly';

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_chat_join_partner_broadcast ON public.partner_portal_accounts;
CREATE TRIGGER trg_chat_join_partner_broadcast
  AFTER INSERT OR UPDATE OF is_active ON public.partner_portal_accounts
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_chat_join_partner_broadcast();

-- ── RPC: opprett partner-private DM ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_partner_private_chat(p_other_user_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_company_id UUID;
  v_room_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  IF NOT public.chat_user_is_partner_portal(v_uid) THEN
    RAISE EXCEPTION 'Kun partnere kan opprette privat partner-chat';
  END IF;

  IF p_other_user_id = v_uid THEN
    RAISE EXCEPTION 'Kan ikke chatte med deg selv';
  END IF;

  IF NOT public.chat_user_is_partner_portal(p_other_user_id) THEN
    RAISE EXCEPTION 'Motparten er ikke partner-bruker';
  END IF;

  v_company_id := public.chat_user_company_id(v_uid);
  IF v_company_id IS DISTINCT FROM public.chat_user_company_id(p_other_user_id) THEN
    RAISE EXCEPTION 'Partnere må tilhøre samme MAVI-bedrift';
  END IF;

  IF public.chat_user_is_blocked(v_uid) OR public.chat_user_is_blocked(p_other_user_id) THEN
    RAISE EXCEPTION 'Chat er blokkert';
  END IF;

  SELECT cr.id INTO v_room_id
  FROM public.chat_rooms cr
  JOIN public.chat_room_members m1 ON m1.room_id = cr.id AND m1.user_id = v_uid AND m1.left_at IS NULL
  JOIN public.chat_room_members m2 ON m2.room_id = cr.id AND m2.user_id = p_other_user_id AND m2.left_at IS NULL
  WHERE cr.room_type = 'partner_private'
    AND cr.company_id = v_company_id
  LIMIT 1;

  IF v_room_id IS NOT NULL THEN
    RETURN v_room_id;
  END IF;

  INSERT INTO public.chat_rooms (company_id, room_type, title, created_by)
  VALUES (v_company_id, 'partner_private', NULL, v_uid)
  RETURNING id INTO v_room_id;

  INSERT INTO public.chat_room_members (room_id, user_id, partner_id, member_role)
  VALUES
    (v_room_id, v_uid, public.chat_user_partner_id(v_uid), 'member'),
    (v_room_id, p_other_user_id, public.chat_user_partner_id(p_other_user_id), 'member');

  RETURN v_room_id;
END;
$$;

-- ── RPC: MAVI → spesifikk partner ─────────────────────────────────────────────

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

  IF NOT public.chat_can_send_direct_to_partner(v_uid) THEN
    RAISE EXCEPTION 'Ingen tilgang til direkte partner-chat';
  END IF;

  v_company_id := public.chat_user_company_id(v_uid);

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

  RETURN v_room_id;
END;
$$;

-- ── RPC: MAVI intern DM/gruppe ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_mavi_internal_chat(
  p_member_ids UUID[],
  p_title TEXT DEFAULT NULL
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
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  IF NOT public.chat_user_is_mavi_employee(v_uid) THEN
    RAISE EXCEPTION 'Kun MAVI-ansatte';
  END IF;

  IF NOT public.profile_has_access(v_uid, 'partners.chat.internal', 'view') THEN
    RAISE EXCEPTION 'Ingen tilgang til intern chat';
  END IF;

  v_company_id := public.chat_user_company_id(v_uid);

  INSERT INTO public.chat_rooms (company_id, room_type, title, created_by)
  VALUES (v_company_id, 'mavi_internal', nullif(trim(p_title), ''), v_uid)
  RETURNING id INTO v_room_id;

  INSERT INTO public.chat_room_members (room_id, user_id, member_role)
  VALUES (v_room_id, v_uid, 'owner')
  ON CONFLICT DO NOTHING;

  FOREACH mid IN ARRAY coalesce(p_member_ids, ARRAY[]::UUID[])
  LOOP
    IF mid IS DISTINCT FROM v_uid
       AND public.chat_user_is_mavi_employee(mid)
       AND public.chat_user_company_id(mid) = v_company_id THEN
      INSERT INTO public.chat_room_members (room_id, user_id, member_role)
      VALUES (v_room_id, mid, 'member')
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;

  RETURN v_room_id;
END;
$$;

-- ── RPC: send melding ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.send_chat_message(
  p_room_id UUID,
  p_body TEXT,
  p_reply_to_id UUID DEFAULT NULL
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
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  IF NOT public.chat_user_can_send(v_uid, p_room_id) THEN
    RAISE EXCEPTION 'Ingen tilgang til å sende i dette rommet';
  END IF;

  IF public.chat_user_is_blocked(v_uid, p_room_id) THEN
    RAISE EXCEPTION 'Du er blokkert fra chat';
  END IF;

  INSERT INTO public.chat_messages (room_id, sender_id, body, reply_to_id)
  VALUES (p_room_id, v_uid, trim(p_body), p_reply_to_id)
  RETURNING id INTO v_message_id;

  v_preview := left(trim(p_body), 120);

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

-- ── RPC: superadmin blokkering ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.chat_block_user(
  p_blocked_user_id UUID,
  p_reason TEXT DEFAULT NULL,
  p_room_id UUID DEFAULT NULL,
  p_until TIMESTAMPTZ DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_id UUID;
  v_company_id UUID;
BEGIN
  IF NOT public.chat_can_moderate(v_uid) THEN
    RAISE EXCEPTION 'Kun superadmin/moderator';
  END IF;

  v_company_id := public.chat_user_company_id(v_uid);

  INSERT INTO public.chat_user_blocks (
    company_id, blocked_user_id, blocked_by, scope, room_id, reason, blocked_until
  )
  VALUES (
    v_company_id,
    p_blocked_user_id,
    v_uid,
    CASE WHEN p_room_id IS NULL THEN 'global' ELSE 'room' END,
    p_room_id,
    nullif(trim(p_reason), ''),
    p_until
  )
  ON CONFLICT (blocked_user_id, scope, room_id) DO UPDATE
    SET blocked_by = EXCLUDED.blocked_by,
        reason = EXCLUDED.reason,
        blocked_until = EXCLUDED.blocked_until
  RETURNING id INTO v_id;

  INSERT INTO public.chat_audit_log (company_id, actor_id, action, room_id, target_user_id, meta)
  VALUES (
    v_company_id,
    v_uid,
    'block_user',
    p_room_id,
    p_blocked_user_id,
    jsonb_build_object('reason', p_reason, 'until', p_until)
  );

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.chat_unblock_user(
  p_blocked_user_id UUID,
  p_room_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF NOT public.chat_can_moderate(v_uid) THEN
    RAISE EXCEPTION 'Kun superadmin/moderator';
  END IF;

  DELETE FROM public.chat_user_blocks
  WHERE blocked_user_id = p_blocked_user_id
    AND (
      (p_room_id IS NULL AND scope = 'global')
      OR (scope = 'room' AND room_id = p_room_id)
    );

  INSERT INTO public.chat_audit_log (company_id, actor_id, action, room_id, target_user_id)
  VALUES (
    public.chat_user_company_id(v_uid),
    v_uid,
    'unblock_user',
    p_room_id,
    p_blocked_user_id
  );
END;
$$;

-- ── RLS ─────────────────────────────────────────────────────────────────────

ALTER TABLE public.chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_room_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_read_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_user_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS chat_rooms_select ON public.chat_rooms;
CREATE POLICY chat_rooms_select ON public.chat_rooms
  FOR SELECT TO authenticated
  USING (public.chat_user_can_access_room(auth.uid(), id));

DROP POLICY IF EXISTS chat_room_members_select ON public.chat_room_members;
CREATE POLICY chat_room_members_select ON public.chat_room_members
  FOR SELECT TO authenticated
  USING (public.chat_user_can_access_room(auth.uid(), room_id));

DROP POLICY IF EXISTS chat_messages_select ON public.chat_messages;
CREATE POLICY chat_messages_select ON public.chat_messages
  FOR SELECT TO authenticated
  USING (
    public.chat_user_can_access_room(auth.uid(), room_id)
    AND moderation_state <> 'hidden'
    OR public.chat_can_moderate(auth.uid())
  );

DROP POLICY IF EXISTS chat_messages_insert ON public.chat_messages;
CREATE POLICY chat_messages_insert ON public.chat_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND public.chat_user_can_send(auth.uid(), room_id)
  );

DROP POLICY IF EXISTS chat_read_state_all ON public.chat_read_state;
CREATE POLICY chat_read_state_all ON public.chat_read_state
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS chat_user_blocks_moderator ON public.chat_user_blocks;
CREATE POLICY chat_user_blocks_moderator ON public.chat_user_blocks
  FOR SELECT TO authenticated
  USING (public.chat_can_moderate(auth.uid()));

DROP POLICY IF EXISTS chat_audit_log_moderator ON public.chat_audit_log;
CREATE POLICY chat_audit_log_moderator ON public.chat_audit_log
  FOR SELECT TO authenticated
  USING (public.chat_can_moderate(auth.uid()));

-- Realtime
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

GRANT EXECUTE ON FUNCTION public.ensure_partner_broadcast_room(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_partner_private_chat(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_mavi_partner_direct_chat(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_mavi_internal_chat(UUID[], TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_chat_message(UUID, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_block_user(UUID, TEXT, UUID, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chat_unblock_user(UUID, UUID) TO authenticated;

COMMENT ON TABLE public.chat_rooms IS
  'Kanaler: mavi_internal, partner_broadcast, partner_private (MAVI-blind), mavi_partner_direct.';
