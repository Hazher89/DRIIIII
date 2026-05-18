-- Vernerunde: arkiv, signatur/stempel, søk, PDF-referanse
ALTER TABLE public.safety_rounds
  ADD COLUMN IF NOT EXISTS template_id TEXT,
  ADD COLUMN IF NOT EXISTS location TEXT,
  ADD COLUMN IF NOT EXISTS archive_number TEXT,
  ADD COLUMN IF NOT EXISTS signature JSONB DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS pdf_url TEXT;

CREATE INDEX IF NOT EXISTS idx_safety_rounds_archive ON public.safety_rounds(archive_number);
CREATE INDEX IF NOT EXISTS idx_safety_rounds_completed ON public.safety_rounds(completed_at DESC);
CREATE INDEX IF NOT EXISTS idx_safety_rounds_title ON public.safety_rounds USING gin (to_tsvector('simple', title));

-- Nummerering ved fullføring
CREATE OR REPLACE FUNCTION public.safety_round_set_archive_number()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.overall_status = 'fullført' AND (NEW.archive_number IS NULL OR NEW.archive_number = '') THEN
    NEW.archive_number := 'VR-' || to_char(COALESCE(NEW.completed_at, now()), 'YYYYMMDD') || '-' ||
      upper(left(replace(NEW.id::text, '-', ''), 6));
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_safety_round_archive ON public.safety_rounds;
CREATE TRIGGER trg_safety_round_archive
  BEFORE INSERT OR UPDATE ON public.safety_rounds
  FOR EACH ROW EXECUTE FUNCTION public.safety_round_set_archive_number();
