-- GDPR: stram inn hvem som kan lese/endre profiler.
-- Ansatt: kun egen rad. Leder: kun avdelinger de leder. Admin: hele bedriften.

DROP POLICY IF EXISTS profiles_select_company ON public.profiles;

CREATE POLICY profiles_select_admin ON public.profiles
  FOR SELECT TO authenticated
  USING (
    public.get_user_role() = 'admin'::public.user_role
    AND company_id IS NOT NULL
    AND company_id = public.get_user_company_id()
  );

CREATE POLICY profiles_select_leader_department ON public.profiles
  FOR SELECT TO authenticated
  USING (
    public.get_user_role() = 'leder'::public.user_role
    AND company_id = public.get_user_company_id()
    AND (
      id = auth.uid()
      OR (
        department_id IS NOT NULL
        AND public.is_department_leader_of(department_id)
      )
    )
  );

-- Leder skal ikke kunne endre andres profiler (kun superadmin/admin).
DROP POLICY IF EXISTS profiles_update_leader_department ON public.profiles;
