-- Bedrifter viste 0 rader når klient hadde companyId (cache/bootstrap)
-- mens profiles.company_id var NULL — partners_select blokkerte da alt.
-- Bruk get_user_company_id() + fyll manglende company_id for interne profiler.

UPDATE public.profiles
SET company_id = public.get_bootstrap_company_id()
WHERE company_id IS NULL
  AND partner_id IS NULL
  AND public.get_bootstrap_company_id() IS NOT NULL;

DROP POLICY IF EXISTS "partners_select" ON public.partners;
CREATE POLICY "partners_select" ON public.partners FOR SELECT USING (
  company_id = public.get_user_company_id()
  OR company_id IN (
    SELECT p.company_id
    FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.company_id IS NOT NULL
  )
  OR id IN (
    SELECT p.partner_id
    FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.partner_id IS NOT NULL
  )
);
