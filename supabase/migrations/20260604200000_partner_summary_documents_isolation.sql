-- Oppsummering (doc_category=summary): kun MAVI superadmin + bil-eier (owner), aldri sjåfør/andre bedrifter.

CREATE OR REPLACE FUNCTION public.trg_partner_document_summary_visibility()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF coalesce(NEW.doc_category, 'general') = 'summary' THEN
    NEW.owner_visible := true;
    NEW.driver_visible := false;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_partner_document_summary_visibility ON public.partner_documents;
CREATE TRIGGER trg_partner_document_summary_visibility
  BEFORE INSERT OR UPDATE OF doc_category, owner_visible, driver_visible ON public.partner_documents
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_partner_document_summary_visibility();

DROP POLICY IF EXISTS "partner_documents_select" ON public.partner_documents;
CREATE POLICY "partner_documents_select" ON public.partner_documents FOR SELECT USING (
  (
    coalesce(doc_category, 'general') = 'summary'
    AND (
      EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = auth.uid() AND p.role::text = 'superadmin'
      )
      OR (
        partner_id IN (
          SELECT p.partner_id FROM public.profiles p
          WHERE p.id = auth.uid()
            AND p.partner_id IS NOT NULL
            AND p.partner_vehicle_id IS NULL
        )
        AND coalesce(owner_visible, true) = true
      )
    )
  )
  OR (
    coalesce(doc_category, 'general') IS DISTINCT FROM 'summary'
    AND (
      (
        company_id IN (
          SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL
        )
      )
      OR (
        partner_id IN (
          SELECT p.partner_id FROM public.profiles p
          WHERE p.id = auth.uid() AND p.partner_id IS NOT NULL AND p.partner_vehicle_id IS NULL
        )
        AND coalesce(owner_visible, true) = true
      )
      OR (
        partner_id IN (
          SELECT p.partner_id FROM public.profiles p
          WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
        )
        AND coalesce(driver_visible, false) = true
      )
    )
  )
);

COMMENT ON POLICY "partner_documents_select" ON public.partner_documents IS
  'summary: superadmin eller bil-eier (egen partner). Øvrige dokumenter: eksisterende MAVI/partner/sjåfør-regler.';
