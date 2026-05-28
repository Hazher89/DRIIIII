-- Partner-dokumentmapper: private vs felles.
-- Felles mapper opprettes på alle partnere i selskapet og videreføres til nye partnere.

CREATE TABLE IF NOT EXISTS public.partner_document_folder_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(company_id, name)
);

CREATE TABLE IF NOT EXISTS public.partner_document_folders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  partner_id UUID NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  visibility TEXT NOT NULL CHECK (visibility IN ('private', 'shared')),
  template_id UUID REFERENCES public.partner_document_folder_templates(id) ON DELETE SET NULL,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(partner_id, name)
);

CREATE INDEX IF NOT EXISTS idx_partner_document_folders_partner
  ON public.partner_document_folders(partner_id, visibility, created_at DESC);

ALTER TABLE public.partner_documents
  ADD COLUMN IF NOT EXISTS folder_id UUID REFERENCES public.partner_document_folders(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_partner_documents_folder
  ON public.partner_documents(folder_id, created_at DESC);

ALTER TABLE public.partner_document_folder_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_document_folders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS partner_document_folder_templates_select ON public.partner_document_folder_templates;
CREATE POLICY partner_document_folder_templates_select ON public.partner_document_folder_templates
  FOR SELECT USING (
    company_id IN (
      SELECT p.company_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.company_id IS NOT NULL
    )
  );

DROP POLICY IF EXISTS partner_document_folder_templates_write ON public.partner_document_folder_templates;
CREATE POLICY partner_document_folder_templates_write ON public.partner_document_folder_templates
  FOR ALL USING (
    company_id IN (
      SELECT p.company_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.company_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x
      WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  )
  WITH CHECK (
    company_id IN (
      SELECT p.company_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.company_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x
      WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  );

DROP POLICY IF EXISTS partner_document_folders_select ON public.partner_document_folders;
CREATE POLICY partner_document_folders_select ON public.partner_document_folders
  FOR SELECT USING (
    company_id IN (
      SELECT p.company_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.company_id IS NOT NULL
    )
  );

DROP POLICY IF EXISTS partner_document_folders_write ON public.partner_document_folders;
CREATE POLICY partner_document_folders_write ON public.partner_document_folders
  FOR ALL USING (
    company_id IN (
      SELECT p.company_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.company_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x
      WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  )
  WITH CHECK (
    company_id IN (
      SELECT p.company_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.company_id IS NOT NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.profiles x
      WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
    )
  );

CREATE OR REPLACE FUNCTION public.create_partner_document_folder(
  p_company_id UUID,
  p_partner_id UUID,
  p_name TEXT,
  p_visibility TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name TEXT;
  v_template_id UUID;
  v_folder_id UUID;
  r_partner RECORD;
BEGIN
  v_name := nullif(trim(p_name), '');
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Mappenavn mangler';
  END IF;
  IF p_visibility NOT IN ('private', 'shared') THEN
    RAISE EXCEPTION 'Ugyldig mappevalg';
  END IF;

  IF p_visibility = 'private' THEN
    INSERT INTO public.partner_document_folders(
      company_id, partner_id, name, visibility, created_by
    )
    VALUES (p_company_id, p_partner_id, v_name, 'private', auth.uid())
    ON CONFLICT (partner_id, name) DO UPDATE SET name = EXCLUDED.name
    RETURNING id INTO v_folder_id;
    RETURN v_folder_id;
  END IF;

  INSERT INTO public.partner_document_folder_templates(
    company_id, name, created_by
  )
  VALUES (p_company_id, v_name, auth.uid())
  ON CONFLICT (company_id, name) DO UPDATE SET is_active = true
  RETURNING id INTO v_template_id;

  FOR r_partner IN
    SELECT id FROM public.partners
    WHERE company_id = p_company_id AND is_active = true
  LOOP
    INSERT INTO public.partner_document_folders(
      company_id, partner_id, name, visibility, template_id, created_by
    )
    VALUES (p_company_id, r_partner.id, v_name, 'shared', v_template_id, auth.uid())
    ON CONFLICT (partner_id, name) DO UPDATE
      SET template_id = EXCLUDED.template_id,
          visibility = 'shared';
  END LOOP;

  SELECT id INTO v_folder_id
  FROM public.partner_document_folders
  WHERE partner_id = p_partner_id AND name = v_name
  LIMIT 1;

  RETURN v_folder_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_seed_shared_folders_for_partner()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.partner_document_folders(
    company_id, partner_id, name, visibility, template_id, created_by
  )
  SELECT
    NEW.company_id,
    NEW.id,
    t.name,
    'shared',
    t.id,
    t.created_by
  FROM public.partner_document_folder_templates t
  WHERE t.company_id = NEW.company_id
    AND t.is_active = true
  ON CONFLICT (partner_id, name) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS seed_shared_folders_for_new_partner ON public.partners;
CREATE TRIGGER seed_shared_folders_for_new_partner
  AFTER INSERT ON public.partners
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_seed_shared_folders_for_partner();

GRANT SELECT, INSERT, UPDATE, DELETE ON public.partner_document_folder_templates TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.partner_document_folders TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_partner_document_folder(UUID, UUID, TEXT, TEXT) TO authenticated;
