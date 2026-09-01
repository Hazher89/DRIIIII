-- Emoji-reaksjoner på meldinger.

CREATE TABLE IF NOT EXISTS public.chat_message_reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL REFERENCES public.chat_messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  emoji TEXT NOT NULL CHECK (char_length(trim(emoji)) BETWEEN 1 AND 8),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (message_id, user_id, emoji)
);

CREATE INDEX IF NOT EXISTS idx_chat_message_reactions_message
  ON public.chat_message_reactions (message_id);

ALTER TABLE public.chat_message_reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS chat_reactions_select ON public.chat_message_reactions;
CREATE POLICY chat_reactions_select ON public.chat_message_reactions
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.chat_messages m
      WHERE m.id = message_id
        AND public.chat_user_can_access_room(auth.uid(), m.room_id)
    )
  );

DROP POLICY IF EXISTS chat_reactions_insert ON public.chat_message_reactions;
CREATE POLICY chat_reactions_insert ON public.chat_message_reactions
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.chat_messages m
      WHERE m.id = message_id
        AND public.chat_user_can_access_room(auth.uid(), m.room_id)
    )
  );

DROP POLICY IF EXISTS chat_reactions_delete ON public.chat_message_reactions;
CREATE POLICY chat_reactions_delete ON public.chat_message_reactions
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

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
  e TEXT := trim(p_emoji);
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Ikke innlogget'; END IF;
  IF e = '' THEN RAISE EXCEPTION 'Ugyldig emoji'; END IF;

  SELECT room_id INTO v_room FROM public.chat_messages WHERE id = p_message_id;
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
  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.chat_toggle_reaction(UUID, TEXT) TO authenticated;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_message_reactions;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;
