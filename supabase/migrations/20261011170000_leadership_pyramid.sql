-- Ledelsespyramide:
-- ansatt → avdelingsleder for avdelingen
-- avdelingsleder → Hazher (driftsleder, ansattnr 25)
-- Hazher → Tommy (daglig leder, ansattnr 100)
-- Tommy og Nico har ingen leder over seg.
-- Superadmin kan overstyre med profiles.reports_to.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS reports_to UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.profile_principal_tier(p_profile_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN p.employee_number IN ('100', '144') THEN 'owner'
    WHEN p.employee_number = '25' THEN 'operations'
    WHEN lower(coalesce(p.email, '')) LIKE '%hazher%'
      OR lower(coalesce(p.full_name, '')) LIKE '%hazher%' THEN 'operations'
    WHEN lower(coalesce(p.full_name, '')) LIKE '%tommy larsen%'
      OR lower(coalesce(p.email, '')) LIKE '%tommy%' THEN 'owner'
    WHEN lower(coalesce(p.full_name, '')) LIKE '%nicola%'
      OR lower(coalesce(p.full_name, '')) LIKE '%nico %' THEN 'owner'
    ELSE NULL
  END
  FROM public.profiles p
  WHERE p.id = p_profile_id;
$$;

CREATE OR REPLACE FUNCTION public._profile_ids_by_tier(
  p_company_id UUID,
  p_tier TEXT
)
RETURNS UUID[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(array_agg(p.id), ARRAY[]::uuid[])
  FROM public.profiles p
  WHERE p.company_id = p_company_id
    AND coalesce(p.is_active, true)
    AND coalesce(p.is_approved, false)
    AND p.partner_id IS NULL
    AND public.profile_principal_tier(p.id) = p_tier
    AND (
      p_tier <> 'owner'
      OR p.employee_number = '100'
      OR (
        p.employee_number IS DISTINCT FROM '144'
        AND lower(coalesce(p.full_name, '')) LIKE '%tommy%'
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.profile_manager_ids(p_profile_id UUID)
RETURNS UUID[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  p public.profiles%ROWTYPE;
  v_tier TEXT;
  v_ids UUID[] := ARRAY[]::uuid[];
BEGIN
  SELECT * INTO p FROM public.profiles WHERE id = p_profile_id;
  IF NOT FOUND THEN
    RETURN ARRAY[]::uuid[];
  END IF;

  IF p.reports_to IS NOT NULL AND p.reports_to IS DISTINCT FROM p.id THEN
    RETURN ARRAY[p.reports_to];
  END IF;

  v_tier := public.profile_principal_tier(p.id);
  IF v_tier = 'owner' THEN
    RETURN ARRAY[]::uuid[];
  END IF;

  IF v_tier = 'operations' THEN
    RETURN public._profile_ids_by_tier(p.company_id, 'owner');
  END IF;

  IF public.profile_is_registered_department_leader(p.id) THEN
    RETURN public._profile_ids_by_tier(p.company_id, 'operations');
  END IF;

  IF p.department_id IS NOT NULL THEN
    SELECT coalesce(array_agg(DISTINCT lid), ARRAY[]::uuid[])
    INTO v_ids
    FROM (
      SELECT d.leader_id AS lid
      FROM public.departments d
      WHERE d.id = p.department_id AND d.leader_id IS NOT NULL
      UNION
      SELECT dl.profile_id
      FROM public.department_leaders dl
      WHERE dl.department_id = p.department_id
    ) src
    WHERE lid IS NOT NULL
      AND lid IS DISTINCT FROM p.id;
  END IF;

  IF coalesce(cardinality(v_ids), 0) = 0 THEN
    RETURN public._profile_ids_by_tier(p.company_id, 'operations');
  END IF;

  RETURN v_ids;
END;
$$;

DROP FUNCTION IF EXISTS public.get_ticket_assignee_options(uuid);

CREATE OR REPLACE FUNCTION public.get_ticket_assignee_options(
  p_department_id uuid DEFAULT NULL,
  p_profile_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_subject uuid;
  v_nearest_ids uuid[] := ARRAY[]::uuid[];
  v_all_leader_ids uuid[] := ARRAY[]::uuid[];
  v_nearest jsonb := '[]'::jsonb;
  v_other jsonb := '[]'::jsonb;
  v_super jsonb := '[]'::jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object(
      'nearest_leaders', '[]'::jsonb,
      'other_leaders', '[]'::jsonb,
      'superadmins', '[]'::jsonb
    );
  END IF;

  SELECT company_id INTO v_company_id
  FROM public.profiles
  WHERE id = auth.uid();

  v_subject := coalesce(p_profile_id, auth.uid());

  IF v_company_id IS NULL THEN
    RETURN jsonb_build_object(
      'nearest_leaders', '[]'::jsonb,
      'other_leaders', '[]'::jsonb,
      'superadmins', '[]'::jsonb
    );
  END IF;

  v_nearest_ids := public.profile_manager_ids(v_subject);

  SELECT COALESCE(array_agg(DISTINCT lid), ARRAY[]::uuid[])
  INTO v_all_leader_ids
  FROM (
    SELECT d.leader_id AS lid
    FROM public.departments d
    WHERE d.company_id = v_company_id AND d.leader_id IS NOT NULL
    UNION
    SELECT dl.profile_id AS lid
    FROM public.department_leaders dl
    JOIN public.departments d ON d.id = dl.department_id
    WHERE d.company_id = v_company_id
  ) src
  WHERE lid IS NOT NULL;

  SELECT COALESCE(jsonb_agg(public._ticket_assignee_profile_json(pr) ORDER BY pr.full_name), '[]'::jsonb)
  INTO v_nearest
  FROM public.profiles pr
  WHERE pr.id = ANY (v_nearest_ids)
    AND pr.company_id = v_company_id
    AND pr.id IS DISTINCT FROM v_subject
    AND COALESCE(pr.is_active, true)
    AND COALESCE(pr.is_approved, false)
    AND pr.partner_id IS NULL;

  SELECT COALESCE(jsonb_agg(public._ticket_assignee_profile_json(pr) ORDER BY pr.full_name), '[]'::jsonb)
  INTO v_other
  FROM public.profiles pr
  WHERE pr.id = ANY (v_all_leader_ids)
    AND NOT (pr.id = ANY (v_nearest_ids))
    AND pr.id IS DISTINCT FROM v_subject
    AND pr.company_id = v_company_id
    AND COALESCE(pr.is_active, true)
    AND COALESCE(pr.is_approved, false)
    AND pr.partner_id IS NULL;

  SELECT COALESCE(jsonb_agg(public._ticket_assignee_profile_json(pr) ORDER BY
    CASE
      WHEN coalesce(pr.employee_number, '') = '100' OR lower(pr.full_name) LIKE '%tommy%' THEN 0
      WHEN coalesce(pr.employee_number, '') = '144' OR lower(pr.full_name) LIKE '%nicola%' THEN 1
      ELSE 2
    END,
    pr.full_name
  ), '[]'::jsonb)
  INTO v_super
  FROM public.profiles pr
  WHERE pr.company_id = v_company_id
    AND COALESCE(pr.is_active, true)
    AND COALESCE(pr.is_approved, false)
    AND pr.partner_id IS NULL
    AND pr.id IS DISTINCT FROM v_subject
    AND public.profile_is_company_principal(pr);

  RETURN jsonb_build_object(
    'nearest_leaders', v_nearest,
    'other_leaders', v_other,
    'superadmins', v_super
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_leaders_on_absence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  employee_name TEXT;
  sms_body TEXT;
  email_body TEXT;
  push_body TEXT;
  push_title TEXT;
  is_update BOOLEAN;
BEGIN
  IF new.status IS DISTINCT FROM 'ventende'::public.absence_status THEN
    RETURN new;
  END IF;

  is_update := tg_op = 'UPDATE';

  IF is_update THEN
    IF old.status IS DISTINCT FROM 'ventende'::public.absence_status THEN
      RETURN new;
    END IF;
    IF old.start_date IS NOT DISTINCT FROM new.start_date
       AND old.end_date IS NOT DISTINCT FROM new.end_date
       AND old.type IS NOT DISTINCT FROM new.type
       AND coalesce(old.comment, '') IS NOT DISTINCT FROM coalesce(new.comment, '') THEN
      RETURN new;
    END IF;
  END IF;

  SELECT coalesce(p.full_name, 'Ansatt') INTO employee_name
  FROM public.profiles p WHERE p.id = new.user_id;

  push_title := CASE WHEN is_update THEN 'Fravær oppdatert' ELSE 'Ny fraværssøknad' END;
  push_body :=
    employee_name || ': ' || coalesce(new.type::text, 'fravær')
    || ' ' || to_char(new.start_date, 'DD.MM')
    || '–' || to_char(new.end_date, 'DD.MM');
  email_body :=
    'Ansatt: ' || employee_name || E'\n'
    || 'Type: ' || coalesce(new.type::text, 'ukjent') || E'\n'
    || 'Periode: ' || to_char(new.start_date, 'DD.MM.YYYY')
    || ' – ' || to_char(new.end_date, 'DD.MM.YYYY') || E'\n'
    || 'Status: ventende'
    || CASE WHEN coalesce(new.comment, '') <> '' THEN E'\n\nKommentar: ' || new.comment ELSE '' END;
  sms_body :=
    'DriftPro: ' || CASE WHEN is_update THEN 'Oppdatert fravær' ELSE 'Nytt fravær' END
    || ' fra ' || employee_name || '.';

  FOR rec IN
    SELECT id, email, coalesce(phone_normalized, phone) AS phone
    FROM public.profiles
    WHERE id = ANY (public.profile_manager_ids(new.user_id))
      AND id IS DISTINCT FROM new.user_id
      AND company_id = new.company_id
      AND is_active = true
      AND is_approved = true
      AND partner_id IS NULL
  LOOP
    PERFORM public.queue_push_to_profile_if_allowed(
      new.company_id, rec.id, push_title, push_body,
      'absence', 'absences', new.id, 'absence_request',
      CASE WHEN is_update THEN 'Fravær oppdatert (push)' ELSE 'Nytt fravær (push)' END,
      false,
      jsonb_build_object(
        'type', 'absence_request',
        'reference_type', 'absences',
        'reference_id', new.id::text,
        'category', 'absence'
      )
    );

    IF coalesce(rec.phone, '') <> '' THEN
      PERFORM public.queue_sms_if_allowed(
        new.company_id, rec.id, rec.phone,
        sms_body, 'absence', 'absences', new.id,
        'absence_request', 'Fravær → leder (SMS)', false
      );
    END IF;

    IF coalesce(rec.email, '') <> '' THEN
      PERFORM public.queue_email_if_allowed(
        new.company_id, rec.id, rec.email,
        push_title, email_body,
        'absence', 'absences', new.id,
        'absence_request', 'Fravær → leder (e-post)', false
      );
    END IF;
  END LOOP;

  RETURN new;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_profile_reports_to(
  p_profile_id UUID,
  p_reports_to UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID;
  v_caller UUID := auth.uid();
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT company_id INTO v_company FROM public.profiles WHERE id = p_profile_id;
  IF v_company IS NULL OR v_company IS DISTINCT FROM public.get_user_company_id() THEN
    RAISE EXCEPTION 'Feil selskap';
  END IF;

  IF public.get_user_role() IS DISTINCT FROM 'superadmin'::public.user_role
     AND public.profile_principal_tier(v_caller) IS NULL THEN
    RAISE EXCEPTION 'Bare superadmin kan velge leder';
  END IF;

  IF p_reports_to IS NOT NULL AND p_reports_to = p_profile_id THEN
    RAISE EXCEPTION 'En person kan ikke være sin egen leder';
  END IF;

  IF p_reports_to IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_reports_to AND company_id = v_company
  ) THEN
    RAISE EXCEPTION 'Lederen finnes ikke i selskapet';
  END IF;

  UPDATE public.profiles
  SET reports_to = p_reports_to
  WHERE id = p_profile_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.profile_manager_ids(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_ticket_assignee_options(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_profile_reports_to(UUID, UUID) TO authenticated;
