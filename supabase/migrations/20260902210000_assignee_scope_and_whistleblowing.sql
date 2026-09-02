-- Avvik/varsling: ansatt melder kun til egen avdelingsleder + Tommy/Nico/Hazher.
-- Anonym anmeldelse: velg leder / ledelse / begge.

-- ── Whistleblowing tabell + mottakervalg ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.whistleblowing_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text NOT NULL,
  image_urls text[] NOT NULL DEFAULT '{}',
  recipient_scope text NOT NULL DEFAULT 'both'
    CHECK (recipient_scope IN ('leader', 'leadership', 'both')),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.whistleblowing_reports
  ADD COLUMN IF NOT EXISTS recipient_scope text;

DO $$
BEGIN
  UPDATE public.whistleblowing_reports
  SET recipient_scope = 'both'
  WHERE recipient_scope IS NULL OR trim(recipient_scope) = '';

  ALTER TABLE public.whistleblowing_reports
    ALTER COLUMN recipient_scope SET DEFAULT 'both';

  ALTER TABLE public.whistleblowing_reports
    ALTER COLUMN recipient_scope SET NOT NULL;
EXCEPTION
  WHEN others THEN NULL;
END $$;

ALTER TABLE public.whistleblowing_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS whistleblowing_insert_authenticated ON public.whistleblowing_reports;
CREATE POLICY whistleblowing_insert_authenticated ON public.whistleblowing_reports
  FOR INSERT TO authenticated
  WITH CHECK (company_id = public.get_user_company_id());

DROP POLICY IF EXISTS whistleblowing_select_leadership ON public.whistleblowing_reports;
CREATE POLICY whistleblowing_select_leadership ON public.whistleblowing_reports
  FOR SELECT TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      public.get_user_role() IN ('superadmin'::public.user_role, 'admin'::public.user_role)
      OR public.profile_is_registered_department_leader(auth.uid())
      OR EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = auth.uid()
          AND (
            coalesce(p.employee_number, '') IN ('25', '100', '144')
            OR lower(p.full_name) LIKE '%tommy%'
            OR lower(p.full_name) LIKE '%nicola%'
            OR lower(p.full_name) LIKE '%hazher%'
          )
      )
    )
  );

-- ── Hjelper: er profil Tommy/Nico/Hazher? ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.profile_is_company_principal(p public.profiles)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    coalesce(p.employee_number, '') IN ('25', '100', '144')
    OR lower(coalesce(p.full_name, '')) LIKE '%tommy%'
    OR lower(coalesce(p.full_name, '')) LIKE '%nicola%'
    OR lower(coalesce(p.full_name, '')) LIKE '%hazher%'
    OR lower(coalesce(p.email, '')) LIKE '%hazher%'
    OR lower(coalesce(p.email, '')) LIKE '%baxigshti%'
    OR lower(coalesce(p.email, '')) LIKE '%tommy%'
    OR lower(coalesce(p.email, '')) LIKE '%nico%';
$$;

CREATE OR REPLACE FUNCTION public._ticket_assignee_profile_json(p public.profiles)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'id', p.id,
    'email', COALESCE(p.email, ''),
    'full_name', COALESCE(p.full_name, 'Bruker'),
    'role', p.role,
    'department_id', p.department_id,
    'company_id', p.company_id,
    'job_title', p.job_title,
    'employee_number', p.employee_number,
    'is_active', COALESCE(p.is_active, true),
    'is_approved', COALESCE(p.is_approved, false)
  );
$$;

-- Kun egen avdelingsleder + Tommy/Nico/Hazher (ikke andre avdelingers ledere).
CREATE OR REPLACE FUNCTION public.get_ticket_assignee_options(
  p_department_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_dept_id uuid;
  v_nearest_ids uuid[] := ARRAY[]::uuid[];
  v_nearest jsonb := '[]'::jsonb;
  v_leadership jsonb := '[]'::jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object(
      'nearest_leaders', '[]'::jsonb,
      'other_leaders', '[]'::jsonb,
      'superadmins', '[]'::jsonb
    );
  END IF;

  SELECT company_id, COALESCE(p_department_id, department_id)
  INTO v_company_id, v_dept_id
  FROM public.profiles
  WHERE id = auth.uid();

  IF v_company_id IS NULL THEN
    RETURN jsonb_build_object(
      'nearest_leaders', '[]'::jsonb,
      'other_leaders', '[]'::jsonb,
      'superadmins', '[]'::jsonb
    );
  END IF;

  IF v_dept_id IS NOT NULL THEN
    SELECT COALESCE(array_agg(DISTINCT lid), ARRAY[]::uuid[])
    INTO v_nearest_ids
    FROM (
      SELECT d.leader_id AS lid
      FROM public.departments d
      WHERE d.id = v_dept_id AND d.leader_id IS NOT NULL
      UNION
      SELECT dl.profile_id AS lid
      FROM public.department_leaders dl
      WHERE dl.department_id = v_dept_id
    ) src
    WHERE lid IS NOT NULL;

    IF COALESCE(cardinality(v_nearest_ids), 0) = 0 THEN
      SELECT COALESCE(array_agg(p.id ORDER BY p.full_name), ARRAY[]::uuid[])
      INTO v_nearest_ids
      FROM public.profiles p
      WHERE p.company_id = v_company_id
        AND p.department_id = v_dept_id
        AND p.role = 'leder'::public.user_role
        AND COALESCE(p.is_active, true)
        AND COALESCE(p.is_approved, false)
        AND p.partner_id IS NULL
        AND NOT public.profile_is_company_principal(p);
    END IF;
  END IF;

  -- Egen leder (ikke ledelsen selv i denne lista)
  SELECT COALESCE(jsonb_agg(public._ticket_assignee_profile_json(p) ORDER BY p.full_name), '[]'::jsonb)
  INTO v_nearest
  FROM public.profiles p
  WHERE p.id = ANY (v_nearest_ids)
    AND p.company_id = v_company_id
    AND COALESCE(p.is_active, true)
    AND COALESCE(p.is_approved, false)
    AND p.partner_id IS NULL
    AND NOT public.profile_is_company_principal(p);

  -- Ledelsen: Tommy, Nico, Hazher
  SELECT COALESCE(jsonb_agg(public._ticket_assignee_profile_json(p) ORDER BY
    CASE
      WHEN coalesce(p.employee_number, '') = '100' OR lower(p.full_name) LIKE '%tommy%' THEN 0
      WHEN coalesce(p.employee_number, '') = '144' OR lower(p.full_name) LIKE '%nicola%' THEN 1
      ELSE 2
    END,
    p.full_name
  ), '[]'::jsonb)
  INTO v_leadership
  FROM public.profiles p
  WHERE p.company_id = v_company_id
    AND COALESCE(p.is_active, true)
    AND COALESCE(p.is_approved, false)
    AND p.partner_id IS NULL
    AND public.profile_is_company_principal(p);

  RETURN jsonb_build_object(
    'nearest_leaders', v_nearest,
    'other_leaders', '[]'::jsonb,
    'superadmins', v_leadership
  );
END;
$$;

COMMENT ON FUNCTION public.get_ticket_assignee_options(uuid) IS
  'Ansatt kan kun velge egen avdelingsleder + Tommy/Nico/Hazher.';

-- ── Varsle mottakere ved anonym anmeldelse ───────────────────────────────────
-- Reporter lagres ikke, men auth.uid() ved INSERT brukes kun til å finne avdeling.

CREATE OR REPLACE FUNCTION public.notify_whistleblowing_report()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  dept_id uuid;
  push_title text := 'Anonym anmeldelse';
  push_body text;
  notify_leader boolean;
  notify_leadership boolean;
BEGIN
  notify_leader := new.recipient_scope IN ('leader', 'both');
  notify_leadership := new.recipient_scope IN ('leadership', 'both');
  push_body := left(coalesce(new.title, 'Ny sak'), 120);

  SELECT department_id INTO dept_id
  FROM public.profiles
  WHERE id = auth.uid();

  IF notify_leadership THEN
    FOR rec IN
      SELECT p.id, p.email, coalesce(p.phone_normalized, p.phone) AS phone
      FROM public.profiles p
      WHERE p.company_id = new.company_id
        AND coalesce(p.is_active, true)
        AND coalesce(p.is_approved, false)
        AND p.partner_id IS NULL
        AND public.profile_is_company_principal(p)
    LOOP
      PERFORM public.queue_push_to_profile_if_allowed(
        new.company_id, rec.id, push_title, push_body,
        'whistleblowing', 'whistleblowing_reports', new.id,
        'general', 'Anonym anmeldelse (push)', false,
        jsonb_build_object(
          'type', 'whistleblowing',
          'reference_type', 'whistleblowing_reports',
          'reference_id', new.id::text
        )
      );
      IF coalesce(rec.phone, '') <> '' THEN
        PERFORM public.queue_sms_if_allowed(
          new.company_id, rec.id, rec.phone,
          'DriftPro: Ny anonym anmeldelse. Logg inn for å lese.',
          'whistleblowing', 'whistleblowing_reports', new.id,
          'general', 'Anonym anmeldelse (SMS)', false
        );
      END IF;
      IF coalesce(rec.email, '') <> '' THEN
        PERFORM public.queue_email_if_allowed(
          new.company_id, rec.id, rec.email,
          push_title,
          'Du har mottatt en anonym anmeldelse.' || E'\n\n'
            || 'Tittel: ' || coalesce(new.title, '') || E'\n\n'
            || left(coalesce(new.description, ''), 2000),
          'whistleblowing', 'whistleblowing_reports', new.id,
          'general', 'Anonym anmeldelse (e-post)', false
        );
      END IF;
    END LOOP;
  END IF;

  IF notify_leader AND dept_id IS NOT NULL THEN
    FOR rec IN
      SELECT DISTINCT p.id, p.email, coalesce(p.phone_normalized, p.phone) AS phone
      FROM public.profiles p
      WHERE p.company_id = new.company_id
        AND coalesce(p.is_active, true)
        AND coalesce(p.is_approved, false)
        AND p.partner_id IS NULL
        AND NOT public.profile_is_company_principal(p)
        AND (
          EXISTS (
            SELECT 1 FROM public.departments d
            WHERE d.id = dept_id AND d.leader_id = p.id
          )
          OR EXISTS (
            SELECT 1 FROM public.department_leaders dl
            WHERE dl.department_id = dept_id AND dl.profile_id = p.id
          )
        )
    LOOP
      PERFORM public.queue_push_to_profile_if_allowed(
        new.company_id, rec.id, push_title, push_body,
        'whistleblowing', 'whistleblowing_reports', new.id,
        'general', 'Anonym anmeldelse (push)', false,
        jsonb_build_object(
          'type', 'whistleblowing',
          'reference_type', 'whistleblowing_reports',
          'reference_id', new.id::text
        )
      );
      IF coalesce(rec.phone, '') <> '' THEN
        PERFORM public.queue_sms_if_allowed(
          new.company_id, rec.id, rec.phone,
          'DriftPro: Ny anonym anmeldelse. Logg inn for å lese.',
          'whistleblowing', 'whistleblowing_reports', new.id,
          'general', 'Anonym anmeldelse (SMS)', false
        );
      END IF;
      IF coalesce(rec.email, '') <> '' THEN
        PERFORM public.queue_email_if_allowed(
          new.company_id, rec.id, rec.email,
          push_title,
          'Du har mottatt en anonym anmeldelse.' || E'\n\n'
            || 'Tittel: ' || coalesce(new.title, '') || E'\n\n'
            || left(coalesce(new.description, ''), 2000),
          'whistleblowing', 'whistleblowing_reports', new.id,
          'general', 'Anonym anmeldelse (e-post)', false
        );
      END IF;
    END LOOP;
  END IF;

  -- Uten avdeling + kun «leder»: eskaler til ledelsen så saken ikke forsvinner.
  IF notify_leader AND NOT notify_leadership AND dept_id IS NULL THEN
    FOR rec IN
      SELECT p.id, p.email, coalesce(p.phone_normalized, p.phone) AS phone
      FROM public.profiles p
      WHERE p.company_id = new.company_id
        AND coalesce(p.is_active, true)
        AND coalesce(p.is_approved, false)
        AND p.partner_id IS NULL
        AND public.profile_is_company_principal(p)
    LOOP
      PERFORM public.queue_push_to_profile_if_allowed(
        new.company_id, rec.id, push_title, push_body,
        'whistleblowing', 'whistleblowing_reports', new.id,
        'general', 'Anonym anmeldelse (push)', false,
        jsonb_build_object(
          'type', 'whistleblowing',
          'reference_type', 'whistleblowing_reports',
          'reference_id', new.id::text
        )
      );
    END LOOP;
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_whistleblowing_report ON public.whistleblowing_reports;
CREATE TRIGGER trg_notify_whistleblowing_report
  AFTER INSERT ON public.whistleblowing_reports
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_whistleblowing_report();
