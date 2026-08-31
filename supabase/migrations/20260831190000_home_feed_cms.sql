-- Live forside-innhold (bilde, video, dokument) for MAVI ansatte og partnere.

CREATE TABLE IF NOT EXISTS public.company_home_feed_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  audience TEXT NOT NULL CHECK (audience IN ('mavi', 'partner')),
  content_type TEXT NOT NULL CHECK (content_type IN ('image', 'video', 'document')),
  title TEXT NOT NULL DEFAULT '',
  caption TEXT,
  storage_path TEXT NOT NULL,
  file_name TEXT,
  mime_type TEXT,
  sort_order INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_company_home_feed_company_audience
  ON public.company_home_feed_items (company_id, audience, is_active, sort_order);

CREATE OR REPLACE FUNCTION public.user_can_manage_home_feed(p_uid UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.profile_has_access(p_uid, 'more.forside', 'edit')
      OR coalesce(
        (
          SELECT (p.access_settings->>'forside_redigering')::boolean
          FROM public.profiles p
          WHERE p.id = p_uid
        ),
        false
      );
$$;

CREATE OR REPLACE FUNCTION public.get_home_feed(p_audience TEXT)
RETURNS SETOF public.company_home_feed_items
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_audience TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN;
  END IF;

  v_audience := lower(trim(coalesce(p_audience, '')));
  IF v_audience NOT IN ('mavi', 'partner') THEN
    RAISE EXCEPTION 'Ugyldig audience: %', p_audience;
  END IF;

  SELECT p.company_id
  INTO v_company_id
  FROM public.profiles p
  WHERE p.id = auth.uid()
    AND p.is_active IS DISTINCT FROM FALSE;

  IF v_company_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT h.*
  FROM public.company_home_feed_items h
  WHERE h.company_id = v_company_id
    AND h.audience = v_audience
    AND h.is_active = true
  ORDER BY h.sort_order ASC, h.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.touch_home_feed_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  NEW.updated_by := auth.uid();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_company_home_feed_updated_at ON public.company_home_feed_items;
CREATE TRIGGER trg_company_home_feed_updated_at
  BEFORE UPDATE ON public.company_home_feed_items
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_home_feed_updated_at();

ALTER TABLE public.company_home_feed_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS company_home_feed_select ON public.company_home_feed_items;
CREATE POLICY company_home_feed_select
  ON public.company_home_feed_items
  FOR SELECT
  TO authenticated
  USING (
    company_id = (
      SELECT p.company_id
      FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.is_active IS DISTINCT FROM FALSE
    )
  );

DROP POLICY IF EXISTS company_home_feed_insert ON public.company_home_feed_items;
CREATE POLICY company_home_feed_insert
  ON public.company_home_feed_items
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.user_can_manage_home_feed(auth.uid())
    AND company_id = (
      SELECT p.company_id
      FROM public.profiles p
      WHERE p.id = auth.uid()
    )
  );

DROP POLICY IF EXISTS company_home_feed_update ON public.company_home_feed_items;
CREATE POLICY company_home_feed_update
  ON public.company_home_feed_items
  FOR UPDATE
  TO authenticated
  USING (
    public.user_can_manage_home_feed(auth.uid())
    AND company_id = (
      SELECT p.company_id
      FROM public.profiles p
      WHERE p.id = auth.uid()
    )
  )
  WITH CHECK (
    public.user_can_manage_home_feed(auth.uid())
    AND company_id = (
      SELECT p.company_id
      FROM public.profiles p
      WHERE p.id = auth.uid()
    )
  );

DROP POLICY IF EXISTS company_home_feed_delete ON public.company_home_feed_items;
CREATE POLICY company_home_feed_delete
  ON public.company_home_feed_items
  FOR DELETE
  TO authenticated
  USING (
    public.user_can_manage_home_feed(auth.uid())
    AND company_id = (
      SELECT p.company_id
      FROM public.profiles p
      WHERE p.id = auth.uid()
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.company_home_feed_items TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_home_feed(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_can_manage_home_feed(UUID) TO authenticated;

ALTER TABLE public.company_home_feed_items REPLICA IDENTITY FULL;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.company_home_feed_items;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TABLE public.company_home_feed_items IS
  'Live forside-innhold (bilde/video/dokument) per audience — MAVI ansatte eller partnere.';
