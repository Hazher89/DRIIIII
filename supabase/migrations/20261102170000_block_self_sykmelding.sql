-- Ansatte skal ikke kunne søke/registrere sykmelding selv.
-- Kun leder/superadmin via absences_insert_manager (for andre).

DROP POLICY IF EXISTS absences_insert_self ON public.absences;

CREATE POLICY absences_insert_self ON public.absences
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND company_id = public.get_user_company_id()
    AND type IS DISTINCT FROM 'sykmelding'::public.absence_type
  );
