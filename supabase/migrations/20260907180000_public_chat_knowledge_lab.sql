-- CCC/butikk chat knowledge lab — superadmin kan mate /montering med rutiner, Q&A og dokumenter.

CREATE TABLE IF NOT EXISTS public.public_chat_knowledge (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  kind text NOT NULL DEFAULT 'note'
    CHECK (kind IN ('document', 'rule', 'qa', 'playbook', 'tone', 'note')),
  title text NOT NULL,
  content text NOT NULL DEFAULT '',
  question text,
  preferred_answer text,
  tags text[] NOT NULL DEFAULT '{}',
  priority int NOT NULL DEFAULT 50,
  published boolean NOT NULL DEFAULT true,
  active boolean NOT NULL DEFAULT true,
  source_filename text,
  storage_path text,
  mime_type text,
  byte_size bigint,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT public_chat_knowledge_title_len CHECK (char_length(title) BETWEEN 1 AND 200),
  CONSTRAINT public_chat_knowledge_content_len CHECK (char_length(content) <= 200000)
);

CREATE INDEX IF NOT EXISTS idx_public_chat_knowledge_company
  ON public.public_chat_knowledge (company_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_public_chat_knowledge_published
  ON public.public_chat_knowledge (published, active, priority DESC)
  WHERE published = true AND active = true;

CREATE INDEX IF NOT EXISTS idx_public_chat_knowledge_tags
  ON public.public_chat_knowledge USING gin (tags);

ALTER TABLE public.public_chat_knowledge ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_company_superadmin(p_company_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.company_id = p_company_id
      AND p.role = 'superadmin'::public.user_role
  );
$$;

DROP POLICY IF EXISTS public_chat_knowledge_select_admin ON public.public_chat_knowledge;
CREATE POLICY public_chat_knowledge_select_admin ON public.public_chat_knowledge
  FOR SELECT TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND public.get_user_role() IN (
      'superadmin'::public.user_role,
      'admin'::public.user_role
    )
  );

DROP POLICY IF EXISTS public_chat_knowledge_write_superadmin ON public.public_chat_knowledge;
CREATE POLICY public_chat_knowledge_write_superadmin ON public.public_chat_knowledge
  FOR ALL TO authenticated
  USING (public.is_company_superadmin(company_id))
  WITH CHECK (public.is_company_superadmin(company_id));

-- Anon/authenticated: only published, external-safe fields for /montering.
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
    AND (
      char_length(trim(k.content)) > 0
      OR char_length(trim(coalesce(k.preferred_answer, ''))) > 0
    )
  ORDER BY k.priority DESC, k.updated_at DESC
  LIMIT greatest(1, least(coalesce(p_limit, 120), 250));
$$;

GRANT EXECUTE ON FUNCTION public.list_public_chat_knowledge_published(int) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.touch_public_chat_knowledge_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_public_chat_knowledge_touch ON public.public_chat_knowledge;
CREATE TRIGGER trg_public_chat_knowledge_touch
  BEFORE UPDATE ON public.public_chat_knowledge
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_public_chat_knowledge_updated_at();

-- Storage for original PDF/TXT uploads (admin only).
DO $$
BEGIN
  INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  VALUES (
    'public-chat-knowledge',
    'public-chat-knowledge',
    false,
    26214400,
    ARRAY[
      'application/pdf',
      'text/plain',
      'text/markdown',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    ]::text[]
  )
  ON CONFLICT (id) DO UPDATE SET
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'Bucket public-chat-knowledge: create manually in Dashboard if needed.';
  WHEN OTHERS THEN
    RAISE NOTICE 'public-chat-knowledge bucket: %', SQLERRM;
END $$;

DROP POLICY IF EXISTS public_chat_knowledge_storage_select ON storage.objects;
CREATE POLICY public_chat_knowledge_storage_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'public-chat-knowledge'
    AND public.get_user_role() IN (
      'superadmin'::public.user_role,
      'admin'::public.user_role
    )
  );

DROP POLICY IF EXISTS public_chat_knowledge_storage_insert ON storage.objects;
CREATE POLICY public_chat_knowledge_storage_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'public-chat-knowledge'
    AND public.get_user_role() = 'superadmin'::public.user_role
  );

DROP POLICY IF EXISTS public_chat_knowledge_storage_delete ON storage.objects;
CREATE POLICY public_chat_knowledge_storage_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'public-chat-knowledge'
    AND public.get_user_role() = 'superadmin'::public.user_role
  );

COMMENT ON TABLE public.public_chat_knowledge IS
  'Live trening for CCC/butikk-chatten (/montering). Superadmin mater rutiner, Q&A og dokumenttekst.';
