-- Skritt på jobb: egen consent-rad skal alltid kunne oppdateres av eier.
-- Tidligere krevde USING også company_id = get_user_company_id(), som feilet
-- når profilens bedrift ble endret mens consent-raden hadde gammel company_id
-- (PostgREST upsert → UPDATE → RLS USING → 42501).

-- Synk eksisterende rader til profilens company_id.
UPDATE public.employee_work_steps_consent c
SET company_id = p.company_id,
    updated_at = now()
FROM public.profiles p
WHERE p.id = c.profile_id
  AND p.company_id IS NOT NULL
  AND c.company_id IS DISTINCT FROM p.company_id;

UPDATE public.employee_work_steps_daily d
SET company_id = p.company_id
FROM public.profiles p
WHERE p.id = d.profile_id
  AND p.company_id IS NOT NULL
  AND d.company_id IS DISTINCT FROM p.company_id;

DROP POLICY IF EXISTS employee_work_steps_consent_select ON public.employee_work_steps_consent;
CREATE POLICY employee_work_steps_consent_select
  ON public.employee_work_steps_consent FOR SELECT TO authenticated
  USING (
    profile_id = auth.uid()
    OR (
      company_id = public.get_user_company_id()
      AND (
        public.is_company_admin()
        OR public.get_user_role() IN (
          'admin'::public.user_role,
          'superadmin'::public.user_role,
          'leder'::public.user_role
        )
        OR public.profile_has_access(auth.uid(), 'more.work_steps_hub', 'view')
      )
    )
  );

DROP POLICY IF EXISTS employee_work_steps_consent_self ON public.employee_work_steps_consent;
CREATE POLICY employee_work_steps_consent_self
  ON public.employee_work_steps_consent FOR ALL TO authenticated
  USING (profile_id = auth.uid())
  WITH CHECK (
    profile_id = auth.uid()
    AND company_id = (SELECT p.company_id FROM public.profiles p WHERE p.id = auth.uid())
  );

DROP POLICY IF EXISTS employee_work_steps_daily_select ON public.employee_work_steps_daily;
CREATE POLICY employee_work_steps_daily_select
  ON public.employee_work_steps_daily FOR SELECT TO authenticated
  USING (
    profile_id = auth.uid()
    OR (
      company_id = public.get_user_company_id()
      AND (
        public.is_company_admin()
        OR public.get_user_role() IN (
          'admin'::public.user_role,
          'superadmin'::public.user_role,
          'leder'::public.user_role
        )
        OR public.profile_has_access(auth.uid(), 'more.work_steps_hub', 'view')
      )
    )
  );

DROP POLICY IF EXISTS employee_work_steps_daily_self_write ON public.employee_work_steps_daily;
CREATE POLICY employee_work_steps_daily_self_write
  ON public.employee_work_steps_daily FOR ALL TO authenticated
  USING (profile_id = auth.uid())
  WITH CHECK (
    profile_id = auth.uid()
    AND company_id = (SELECT p.company_id FROM public.profiles p WHERE p.id = auth.uid())
  );
