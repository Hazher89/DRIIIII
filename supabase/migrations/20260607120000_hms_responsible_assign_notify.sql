-- HMS: ansvarlig-person, synlighet for tildelte, e-post/SMS ved tildeling, flere maler.

-- ── Utvid tilgang: ansvarlig skal se og oppdatere ───────────────────────────

CREATE OR REPLACE FUNCTION public.hms_can_access_record(
  p_company_id uuid,
  p_department_id uuid,
  p_owner_id uuid,
  p_responsible_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p_company_id = public.get_user_company_id()
    AND (
      public.is_company_admin()
      OR p_owner_id = auth.uid()
      OR p_responsible_id = auth.uid()
      OR (
        public.get_user_role() = 'leder'::public.user_role
        AND (
          p_department_id IS NOT DISTINCT FROM public.get_user_department_id()
          OR public.is_department_leader_of(p_department_id)
          OR EXISTS (
            SELECT 1
            FROM public.profiles rep
            WHERE rep.id = p_owner_id
              AND rep.department_id IS NOT DISTINCT FROM public.get_user_department_id()
          )
        )
      )
      OR (
        public.get_user_role() = 'ansatt'::public.user_role
        AND (
          p_owner_id = auth.uid()
          OR p_responsible_id = auth.uid()
          OR p_department_id IS NOT DISTINCT FROM public.get_user_department_id()
        )
      )
    );
$$;

ALTER TABLE public.sja_forms
  ADD COLUMN IF NOT EXISTS responsible_person uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_risk_assessments_responsible
  ON public.risk_assessments (responsible_person)
  WHERE responsible_person IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sja_forms_responsible
  ON public.sja_forms (responsible_person)
  WHERE responsible_person IS NOT NULL;

-- ── RLS: inkluder ansvarlig ─────────────────────────────────────────────────

DROP POLICY IF EXISTS risk_assessments_select_scoped ON public.risk_assessments;
CREATE POLICY risk_assessments_select_scoped ON public.risk_assessments
  FOR SELECT TO authenticated
  USING (
    public.hms_can_access_record(
      company_id, department_id, created_by, responsible_person
    )
  );

DROP POLICY IF EXISTS risk_assessments_update_scoped ON public.risk_assessments;
CREATE POLICY risk_assessments_update_scoped ON public.risk_assessments
  FOR UPDATE TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      created_by = auth.uid()
      OR responsible_person = auth.uid()
      OR public.is_company_admin()
      OR public.get_user_role() = 'leder'::public.user_role
    )
  )
  WITH CHECK (company_id = public.get_user_company_id());

DROP POLICY IF EXISTS sja_forms_select_scoped ON public.sja_forms;
CREATE POLICY sja_forms_select_scoped ON public.sja_forms
  FOR SELECT TO authenticated
  USING (
    public.hms_can_access_record(
      company_id, department_id, created_by, responsible_person
    )
  );

DROP POLICY IF EXISTS sja_forms_update_scoped ON public.sja_forms;
CREATE POLICY sja_forms_update_scoped ON public.sja_forms
  FOR UPDATE TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      created_by = auth.uid()
      OR responsible_person = auth.uid()
      OR public.is_company_admin()
      OR public.get_user_role() = 'leder'::public.user_role
    )
  )
  WITH CHECK (company_id = public.get_user_company_id());

-- ── Varsle ansvarlig (e-post + SMS + push) ──────────────────────────────────

CREATE OR REPLACE FUNCTION public.hms_notify_assigned_responsible(
  p_company_id uuid,
  p_user_id uuid,
  p_title text,
  p_module_label text,
  p_reference_type text,
  p_reference_id uuid,
  p_category text,
  p_creator_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email text;
  v_phone text;
  v_name text;
  v_creator text;
  v_subject text;
  v_body text;
  v_sms text;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  SELECT coalesce(full_name, 'Ansatt'), email, phone
  INTO v_name, v_email, v_phone
  FROM public.profiles
  WHERE id = p_user_id;

  SELECT coalesce(full_name, 'Kollega')
  INTO v_creator
  FROM public.profiles
  WHERE id = p_creator_id;

  v_subject := format('DriftPro: Du er ansvarlig for %s', p_module_label);
  v_body :=
    format('Hei %s,', v_name) || E'\n\n'
    || v_creator || ' har tildelt deg ansvaret for:' || E'\n'
    || coalesce(p_title, 'Uten tittel') || E'\n\n'
    || 'Logg inn i DriftPro for å vurdere og behandle oppgaven.' || E'\n';

  v_sms :=
    'DriftPro: Du er ansvarlig for '
    || p_module_label || ' «'
    || left(coalesce(p_title, ''), 45)
    || '». Logg inn og vurder.';

  IF coalesce(v_email, '') <> '' THEN
    PERFORM public.queue_email(
      p_company_id,
      v_email,
      v_subject,
      v_body,
      p_category,
      p_reference_type,
      p_reference_id,
      p_category,
      p_user_id,
      p_creator_id
    );
  END IF;

  PERFORM public.queue_sms_if_allowed(
    p_company_id,
    p_user_id,
    v_phone,
    v_sms,
    p_category,
    p_reference_type,
    p_reference_id,
    'hms'
  );

  PERFORM public.hms_push_notification(
    p_user_id,
    p_company_id,
    v_subject,
    left(v_sms, 200),
    jsonb_build_object(
      'reference_type', p_reference_type,
      'reference_id', p_reference_id,
      'category', p_category
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.hms_notify_risk_responsible()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.responsible_person IS NOT NULL
     AND (
       TG_OP = 'INSERT'
       OR OLD.responsible_person IS DISTINCT FROM NEW.responsible_person
     ) THEN
    PERFORM public.hms_notify_assigned_responsible(
      NEW.company_id,
      NEW.responsible_person,
      NEW.title,
      'risikoanalyse',
      'risk_assessments',
      NEW.id,
      'hms_risk_assigned',
      NEW.created_by
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_hms_notify_risk_responsible ON public.risk_assessments;
CREATE TRIGGER trg_hms_notify_risk_responsible
  AFTER INSERT OR UPDATE OF responsible_person, title
  ON public.risk_assessments
  FOR EACH ROW
  EXECUTE FUNCTION public.hms_notify_risk_responsible();

CREATE OR REPLACE FUNCTION public.hms_notify_sja_responsible()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.responsible_person IS NOT NULL
     AND (
       TG_OP = 'INSERT'
       OR OLD.responsible_person IS DISTINCT FROM NEW.responsible_person
     ) THEN
    PERFORM public.hms_notify_assigned_responsible(
      NEW.company_id,
      NEW.responsible_person,
      NEW.title,
      'SJA',
      'sja_forms',
      NEW.id,
      'hms_sja_assigned',
      NEW.created_by
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_hms_notify_sja_responsible ON public.sja_forms;
CREATE TRIGGER trg_hms_notify_sja_responsible
  AFTER INSERT OR UPDATE OF responsible_person, title
  ON public.sja_forms
  FOR EACH ROW
  EXECUTE FUNCTION public.hms_notify_sja_responsible();

-- Ikke varsle alle ledere når ansvarlig er satt (unngå støy)
CREATE OR REPLACE FUNCTION public.hms_notify_on_risk_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.responsible_person IS NULL THEN
    PERFORM public.hms_notify_nearest_leaders(
      NEW.company_id,
      NEW.department_id,
      NEW.created_by,
      coalesce(NEW.title, 'Ny ROS-analyse'),
      'hms_ros_new',
      'risk_assessments',
      NEW.id,
      'hms'
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.hms_notify_on_sja_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.responsible_person IS NULL THEN
    PERFORM public.hms_notify_nearest_leaders(
      NEW.company_id,
      NEW.department_id,
      NEW.created_by,
      coalesce(NEW.title, 'Ny SJA'),
      'hms_sja_new',
      'sja_forms',
      NEW.id,
      'hms'
    );
  END IF;
  RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.hms_notify_assigned_responsible TO authenticated, service_role;

-- ── Flere maler: lager og logistikk ─────────────────────────────────────────

INSERT INTO public.hms_ros_templates (
  company_id, template_key, title, description, area, scenario_category,
  initial_probability, initial_consequence, existing_measures, proposed_measures, sort_order
)
SELECT v.company_id, v.template_key, v.title, v.description, v.area, v.scenario_category,
       v.initial_probability, v.initial_consequence, v.existing_measures, v.proposed_measures, v.sort_order
FROM (VALUES
  (NULL::uuid, 'truck_lager', 'Truckkjøring i lagerhall', 'Kollisjon med gående, tipputstyr eller reoler', 'Lager', 'Truck',
   4, 4, 'Truckførerbevis, fartsgrense, speil', 'Gående-soner, blått lys, kollektivsikring', 40),
  (NULL::uuid, 'pall_stabling', 'Stabling av paller', 'Veltende pall eller fallende gods', 'Lager', 'Stabling',
   3, 4, 'Max høyde-skilt, shrink', 'Inspeksjon av paller, opplæring i stabling', 50),
  (NULL::uuid, 'lossing_container', 'Lossing av container', 'Fallende gods ved åpning, klemskade', 'Terminal', 'Lossing',
   3, 5, 'Lossingssone, verneutstyr', 'Sikring av dør, to-person prinsipp', 60),
  (NULL::uuid, 'manuelt_løft', 'Manuelt løft på lager', 'Ryggskade ved gjentatte løft', 'Lager', 'Ergonomi',
   4, 3, 'Løfteveiledning', 'Hjelpemidler, roterende oppgaver', 70),
  (NULL::uuid, 'last_sikring', 'Lastsikring på bil', 'Last som forskyver seg under kjøring', 'Transport', 'Lastsikring',
   3, 5, 'Stropper, surreregler', 'Sjekkliste før avgang, egenkontroll', 80),
  (NULL::uuid, 'natt_kjoring', 'Nattkjøring / distribusjon', 'Tretthet, dårlig sikt, vilt', 'Logistikk', 'Kjøring',
   3, 4, 'Kjøre- og hviletid', 'Ruteplan, hvilepauser, varsling ved forsinkelse', 90)
) AS v(company_id, template_key, title, description, area, scenario_category,
       initial_probability, initial_consequence, existing_measures, proposed_measures, sort_order)
WHERE NOT EXISTS (
  SELECT 1 FROM public.hms_ros_templates t
  WHERE t.company_id IS NULL AND t.template_key = v.template_key
);

INSERT INTO public.hms_ticket_templates (
  company_id, template_key, title, description_template, category, severity, hms_domain, sort_order
)
SELECT v.company_id, v.template_key, v.title, v.description_template, v.category, v.severity, v.hms_domain, v.sort_order
FROM (VALUES
  (NULL::uuid, 'reol_kollaps', 'Reol/nært miss på lager', 'Beskriv hendelsen, reol/seksjon og om noe falt.', 'Lager', 'hoy'::public.ticket_severity, 'logistikk'::public.hms_domain, 60),
  (NULL::uuid, 'truck_near_miss', 'Nestenulykke med truck', 'Hvor skjedde det, fart, sikt, tiltak tatt.', 'Truck', 'hoy'::public.ticket_severity, 'logistikk'::public.hms_domain, 70)
) AS v(company_id, template_key, title, description_template, category, severity, hms_domain, sort_order)
WHERE NOT EXISTS (
  SELECT 1 FROM public.hms_ticket_templates t
  WHERE t.company_id IS NULL AND t.template_key = v.template_key
);
