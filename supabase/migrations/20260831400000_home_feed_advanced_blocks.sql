-- Avansert forside-CMS: tekst, YouTube, lenker, spacer, karusell, planlegging, grid.

ALTER TABLE public.company_home_feed_items
  ALTER COLUMN storage_path DROP NOT NULL;

ALTER TABLE public.company_home_feed_items
  ADD COLUMN IF NOT EXISTS content_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES public.company_home_feed_items(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS schedule_start TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS schedule_end TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS target_portals TEXT[],
  ADD COLUMN IF NOT EXISTS priority INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS pinned BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS version_snapshots JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.company_home_feed_items
  DROP CONSTRAINT IF EXISTS company_home_feed_items_content_type_check;

ALTER TABLE public.company_home_feed_items
  ADD CONSTRAINT company_home_feed_items_content_type_check
  CHECK (content_type IN (
    'image', 'video', 'document', 'text', 'youtube', 'link', 'spacer', 'carousel'
  ));

CREATE INDEX IF NOT EXISTS idx_company_home_feed_parent
  ON public.company_home_feed_items (parent_id)
  WHERE parent_id IS NOT NULL;

COMMENT ON COLUMN public.company_home_feed_items.content_json IS
  'Type-spesifikt innhold: youtube_url, link_url, body_text, carousel slide_ids, badge, countdown, osv.';

-- Oppdatert henting med planlegging, portal-målgruppe og karusell-barn.
DROP FUNCTION IF EXISTS public.get_home_feed(TEXT);

CREATE OR REPLACE FUNCTION public.get_home_feed(
  p_audience TEXT,
  p_portal TEXT DEFAULT NULL
)
RETURNS SETOF public.company_home_feed_items
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_audience TEXT;
  v_portal TEXT;
  v_now TIMESTAMPTZ := now();
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN;
  END IF;

  v_audience := lower(trim(coalesce(p_audience, '')));
  IF v_audience NOT IN ('mavi', 'partner') THEN
    RAISE EXCEPTION 'Ugyldig audience: %', p_audience;
  END IF;

  v_portal := lower(trim(coalesce(p_portal, '')));
  IF v_portal = '' THEN
    v_portal := NULL;
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
    AND h.parent_id IS NULL
    AND (h.schedule_start IS NULL OR h.schedule_start <= v_now)
    AND (h.schedule_end IS NULL OR h.schedule_end >= v_now)
    AND (
      h.target_portals IS NULL
      OR cardinality(h.target_portals) = 0
      OR v_portal IS NULL
      OR v_portal = ANY(h.target_portals)
    )
  ORDER BY h.pinned DESC, h.priority DESC, h.sort_order ASC, h.created_at DESC;
END;
$$;

-- Hent karusell-barn for et gitt foreldre-element.
CREATE OR REPLACE FUNCTION public.get_home_feed_carousel_slides(p_parent_id UUID)
RETURNS SETOF public.company_home_feed_items
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id UUID;
  v_now TIMESTAMPTZ := now();
BEGIN
  IF auth.uid() IS NULL OR p_parent_id IS NULL THEN
    RETURN;
  END IF;

  SELECT p.company_id INTO v_company_id
  FROM public.profiles p
  WHERE p.id = auth.uid();

  IF v_company_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT h.*
  FROM public.company_home_feed_items h
  WHERE h.company_id = v_company_id
    AND h.parent_id = p_parent_id
    AND h.is_active = true
    AND (h.schedule_start IS NULL OR h.schedule_start <= v_now)
    AND (h.schedule_end IS NULL OR h.schedule_end >= v_now)
  ORDER BY h.sort_order ASC, h.created_at ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_home_feed(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_home_feed_carousel_slides(UUID) TO authenticated;
