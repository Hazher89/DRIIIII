-- Channel for Chat Lab knowledge: public (/montering) vs internal (Spør DriftPro).

ALTER TABLE public.public_chat_knowledge
  ADD COLUMN IF NOT EXISTS channel text NOT NULL DEFAULT 'public';

DO $$
BEGIN
  ALTER TABLE public.public_chat_knowledge
    DROP CONSTRAINT IF EXISTS public_chat_knowledge_channel_check;
  ALTER TABLE public.public_chat_knowledge
    ADD CONSTRAINT public_chat_knowledge_channel_check
    CHECK (channel IN ('public', 'internal', 'both'));
EXCEPTION
  WHEN others THEN
    RAISE NOTICE 'channel constraint: %', SQLERRM;
END $$;

CREATE INDEX IF NOT EXISTS idx_public_chat_knowledge_channel
  ON public.public_chat_knowledge (channel, published, active, priority DESC);

-- Public RPC: only public + both
CREATE OR REPLACE FUNCTION public.list_public_chat_knowledge_published(
  p_limit int DEFAULT 120
)
RETURNS TABLE (
  id uuid,
  kind text,
  title text,
  content text,
  question text,
  preferred_answer text,
  tags text[],
  priority int,
  updated_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    k.id,
    k.kind,
    k.title,
    CASE
      WHEN k.kind = 'qa' AND coalesce(k.preferred_answer, '') <> ''
        THEN coalesce(k.preferred_answer, '')
      ELSE left(k.content, 12000)
    END AS content,
    k.question,
    k.preferred_answer,
    k.tags,
    k.priority,
    k.updated_at
  FROM public.public_chat_knowledge k
  WHERE k.published = true
    AND k.active = true
    AND k.channel IN ('public', 'both')
    AND (
      char_length(trim(k.content)) > 0
      OR char_length(trim(coalesce(k.preferred_answer, ''))) > 0
    )
  ORDER BY k.priority DESC, k.updated_at DESC
  LIMIT greatest(1, least(coalesce(p_limit, 120), 250));
$$;

GRANT EXECUTE ON FUNCTION public.list_public_chat_knowledge_published(int) TO anon, authenticated;

COMMENT ON COLUMN public.public_chat_knowledge.channel IS
  'public = /montering CCC-chat; internal = Spør DriftPro for ansatte; both = begge';
