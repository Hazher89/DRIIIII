-- Konto-sletting: bruker sender søknad; kun superadmin fullfører.
-- Lovpålagt HMS/HR-historikk kan beholdes ved faktisk sletting (eksisterende hard-delete).

CREATE TABLE IF NOT EXISTS public.account_deletion_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  profile_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  full_name TEXT,
  email TEXT,
  employee_number TEXT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'completed', 'cancelled')),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  due_by DATE NOT NULL DEFAULT ((CURRENT_DATE + 15)),
  completed_at TIMESTAMPTZ,
  completed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  note TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS account_deletion_requests_one_pending
  ON public.account_deletion_requests (profile_id)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_account_deletion_requests_company_pending
  ON public.account_deletion_requests (company_id, status, requested_at DESC);

ALTER TABLE public.account_deletion_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS account_deletion_requests_select ON public.account_deletion_requests;
CREATE POLICY account_deletion_requests_select
  ON public.account_deletion_requests
  FOR SELECT TO authenticated
  USING (
    profile_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role = 'superadmin'::public.user_role
        AND (
          p.company_id = account_deletion_requests.company_id
          OR p.company_id IS NULL
        )
    )
  );

CREATE OR REPLACE FUNCTION public.request_account_deletion()
RETURNS public.account_deletion_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_profile public.profiles%ROWTYPE;
  v_row public.account_deletion_requests%ROWTYPE;
  v_admin RECORD;
  v_title TEXT := 'Søknad om sletting av konto';
  v_body TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = v_uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profil ikke funnet';
  END IF;

  IF v_profile.company_id IS NULL THEN
    RAISE EXCEPTION 'Mangler bedriftstilknytning';
  END IF;

  SELECT * INTO v_row
  FROM public.account_deletion_requests
  WHERE profile_id = v_uid AND status = 'pending'
  LIMIT 1;

  IF FOUND THEN
    RETURN v_row;
  END IF;

  INSERT INTO public.account_deletion_requests (
    company_id,
    profile_id,
    full_name,
    email,
    employee_number,
    status,
    due_by,
    note
  ) VALUES (
    v_profile.company_id,
    v_uid,
    v_profile.full_name,
    v_profile.email,
    v_profile.employee_number,
    'pending',
    (CURRENT_DATE + 15),
    'Bruker har bedt om sletting. Lovpålagte data kan beholdes.'
  )
  RETURNING * INTO v_row;

  v_body := coalesce(nullif(trim(v_profile.full_name), ''), 'En bruker')
    || ' har søkt om å slette kontoen. Frist: '
    || to_char(v_row.due_by, 'DD.MM.YYYY')
    || '. Kun superadmin kan fullføre slettingen.';

  FOR v_admin IN
    SELECT p.id
    FROM public.profiles p
    WHERE p.role = 'superadmin'::public.user_role
      AND coalesce(p.is_active, true)
      AND (
        p.company_id = v_profile.company_id
        OR p.company_id IS NULL
      )
      AND p.id <> v_uid
  LOOP
    BEGIN
      PERFORM public.queue_push_to_profile_if_allowed(
        v_profile.company_id,
        v_admin.id,
        v_title,
        v_body,
        'account_deletion',
        'account_deletion_requests',
        v_row.id,
        'general',
        'Konto-sletting (push)',
        false,
        jsonb_build_object(
          'type', 'account_deletion',
          'reference_type', 'account_deletion_requests',
          'reference_id', v_row.id::text,
          'profile_id', v_uid::text
        )
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'account_deletion push failed for %: %', v_admin.id, SQLERRM;
    END;
  END LOOP;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.request_account_deletion() TO authenticated;

CREATE OR REPLACE FUNCTION public.complete_account_deletion_request(p_profile_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me public.profiles%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_me FROM public.profiles WHERE id = auth.uid();
  IF NOT FOUND OR v_me.role <> 'superadmin'::public.user_role THEN
    RAISE EXCEPTION 'Kun superadmin kan fullføre sletting';
  END IF;

  UPDATE public.account_deletion_requests
  SET status = 'completed',
      completed_at = now(),
      completed_by = auth.uid()
  WHERE profile_id = p_profile_id
    AND status = 'pending';
END;
$$;

GRANT EXECUTE ON FUNCTION public.complete_account_deletion_request(UUID) TO authenticated;

COMMENT ON TABLE public.account_deletion_requests IS
  'GDPR/App Store: bruker søker sletting; superadmin utfører innen 15 dager.';
