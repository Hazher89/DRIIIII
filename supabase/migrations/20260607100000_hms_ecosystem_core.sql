-- HMS-økosystem: Avvik ↔ ROS ↔ SJA
-- Tabeller, utvidelser, RLS, lagring og automatiske varsler.

-- ── ENUMs ───────────────────────────────────────────────────────────────────

DO $$ BEGIN
  CREATE TYPE public.hms_domain AS ENUM ('hms', 'kvalitet', 'logistikk');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.hms_sync_status AS ENUM ('pending', 'syncing', 'synced', 'failed');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.hms_ros_signal_status AS ENUM ('active', 'acknowledged', 'dismissed');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.hms_signature_method AS ENUM ('digital', 'qr', 'pin');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TYPE public.sja_status ADD VALUE IF NOT EXISTS 'venter_signatur';
ALTER TYPE public.sja_status ADD VALUE IF NOT EXISTS 'i_gang';
ALTER TYPE public.sja_status ADD VALUE IF NOT EXISTS 'utlopt';

-- ── Felles tilgangshjelpere ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.hms_can_access_record(
  p_company_id uuid,
  p_department_id uuid,
  p_owner_id uuid
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
          OR p_department_id IS NOT DISTINCT FROM public.get_user_department_id()
        )
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.hms_can_view_sensitive_ticket(p_ticket_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.tickets t
    WHERE t.id = p_ticket_id
      AND t.company_id = public.get_user_company_id()
      AND (
        public.is_company_admin()
        OR public.get_user_role() = 'leder'::public.user_role
          AND (
            public.is_department_leader_of(t.department_id)
            OR t.department_id IS NOT DISTINCT FROM public.get_user_department_id()
          )
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.hms_resolve_department_leader_ids(p_department_id uuid)
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT dl.profile_id
  FROM public.department_leaders dl
  WHERE dl.department_id = p_department_id
  UNION
  SELECT d.leader_id
  FROM public.departments d
  WHERE d.id = p_department_id
    AND d.leader_id IS NOT NULL;
$$;

-- ── AVVIK: utvidelser ───────────────────────────────────────────────────────

ALTER TABLE public.tickets
  ADD COLUMN IF NOT EXISTS hms_domain public.hms_domain NOT NULL DEFAULT 'hms',
  ADD COLUMN IF NOT EXISTS template_key text,
  ADD COLUMN IF NOT EXISTS video_urls text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS media_paths text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS observed_at timestamptz,
  ADD COLUMN IF NOT EXISTS completed_measures text,
  ADD COLUMN IF NOT EXISTS escalated_to uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS escalated_at timestamptz,
  ADD COLUMN IF NOT EXISTS escalation_reason text,
  ADD COLUMN IF NOT EXISTS linked_risk_assessment_id uuid REFERENCES public.risk_assessments(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS linked_sja_id uuid REFERENCES public.sja_forms(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS has_personal_injury boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS offline_client_id uuid,
  ADD COLUMN IF NOT EXISTS synced_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_tickets_hms_domain
  ON public.tickets (company_id, hms_domain, status);

CREATE INDEX IF NOT EXISTS idx_tickets_category_recent
  ON public.tickets (company_id, category, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_tickets_offline_client
  ON public.tickets (offline_client_id)
  WHERE offline_client_id IS NOT NULL;

-- GDPR: personsensitive avviksfelter (aldri i fritekstsøk)
CREATE TABLE IF NOT EXISTS public.hms_ticket_sensitive (
  ticket_id uuid PRIMARY KEY REFERENCES public.tickets(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  involved_person_name text,
  injury_description text,
  medical_notes text,
  encrypted_payload bytea,
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hms_ticket_sensitive_company
  ON public.hms_ticket_sensitive (company_id);

-- Hurtigmaler for avvik
CREATE TABLE IF NOT EXISTS public.hms_ticket_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  template_key text NOT NULL,
  title text NOT NULL,
  description_template text NOT NULL DEFAULT '',
  category text,
  severity public.ticket_severity NOT NULL DEFAULT 'middels',
  hms_domain public.hms_domain NOT NULL DEFAULT 'hms',
  sort_order int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, template_key)
);

-- Leder-historikk / tiltak på avvik
CREATE TABLE IF NOT EXISTS public.hms_ticket_leader_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES public.tickets(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  actor_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  action_type text NOT NULL CHECK (action_type IN ('tiltak', 'rotarsak', 'kommentar', 'eskalering', 'lukking')),
  body text NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hms_ticket_leader_actions_ticket
  ON public.hms_ticket_leader_actions (ticket_id, created_at DESC);

-- ── ROS: utvidelser ─────────────────────────────────────────────────────────

ALTER TABLE public.risk_assessments
  ADD COLUMN IF NOT EXISTS initial_probability int CHECK (initial_probability BETWEEN 1 AND 5),
  ADD COLUMN IF NOT EXISTS initial_consequence int CHECK (initial_consequence BETWEEN 1 AND 5),
  ADD COLUMN IF NOT EXISTS residual_probability int CHECK (residual_probability BETWEEN 1 AND 5),
  ADD COLUMN IF NOT EXISTS residual_consequence int CHECK (residual_consequence BETWEEN 1 AND 5),
  ADD COLUMN IF NOT EXISTS template_key text,
  ADD COLUMN IF NOT EXISTS scenario_category text,
  ADD COLUMN IF NOT EXISTS avvik_boosted boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS avvik_signal_count int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS avvik_last_signal_at timestamptz,
  ADD COLUMN IF NOT EXISTS linked_ticket_category text,
  ADD COLUMN IF NOT EXISTS offline_client_id uuid,
  ADD COLUMN IF NOT EXISTS synced_at timestamptz;

UPDATE public.risk_assessments
SET
  initial_probability = COALESCE(initial_probability, probability),
  initial_consequence = COALESCE(initial_consequence, consequence),
  residual_probability = COALESCE(residual_probability, probability),
  residual_consequence = COALESCE(residual_consequence, consequence)
WHERE initial_probability IS NULL
   OR initial_consequence IS NULL
   OR residual_probability IS NULL
   OR residual_consequence IS NULL;

ALTER TABLE public.risk_assessments
  ALTER COLUMN initial_probability SET DEFAULT 3,
  ALTER COLUMN initial_consequence SET DEFAULT 3,
  ALTER COLUMN residual_probability SET DEFAULT 3,
  ALTER COLUMN residual_consequence SET DEFAULT 3;

CREATE INDEX IF NOT EXISTS idx_risk_assessments_scenario
  ON public.risk_assessments (company_id, scenario_category, status);

CREATE TABLE IF NOT EXISTS public.hms_ros_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  template_key text NOT NULL,
  title text NOT NULL,
  description text,
  area text,
  scenario_category text,
  initial_probability int NOT NULL DEFAULT 3 CHECK (initial_probability BETWEEN 1 AND 5),
  initial_consequence int NOT NULL DEFAULT 3 CHECK (initial_consequence BETWEEN 1 AND 5),
  existing_measures text,
  proposed_measures text,
  sort_order int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, template_key)
);

CREATE TABLE IF NOT EXISTS public.hms_ros_avvik_signals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  department_id uuid REFERENCES public.departments(id) ON DELETE SET NULL,
  risk_assessment_id uuid REFERENCES public.risk_assessments(id) ON DELETE SET NULL,
  ticket_category text NOT NULL,
  ticket_count int NOT NULL,
  window_days int NOT NULL DEFAULT 30,
  status public.hms_ros_signal_status NOT NULL DEFAULT 'active',
  sample_ticket_ids uuid[] NOT NULL DEFAULT '{}',
  acknowledged_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  acknowledged_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hms_ros_avvik_signals_active
  ON public.hms_ros_avvik_signals (company_id, status, ticket_category);

-- ── SJA: utvidelser ─────────────────────────────────────────────────────────

ALTER TABLE public.sja_forms
  ADD COLUMN IF NOT EXISTS valid_from timestamptz,
  ADD COLUMN IF NOT EXISTS valid_until timestamptz,
  ADD COLUMN IF NOT EXISTS active_window_hours int NOT NULL DEFAULT 8,
  ADD COLUMN IF NOT EXISTS team_pin_hash text,
  ADD COLUMN IF NOT EXISTS qr_token uuid NOT NULL DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS template_key text,
  ADD COLUMN IF NOT EXISTS source_template_id uuid,
  ADD COLUMN IF NOT EXISTS required_signatures int NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS work_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS expired_notified_at timestamptz,
  ADD COLUMN IF NOT EXISTS offline_client_id uuid,
  ADD COLUMN IF NOT EXISTS synced_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS idx_sja_forms_qr_token
  ON public.sja_forms (qr_token);

CREATE TABLE IF NOT EXISTS public.hms_sja_steps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sja_id uuid NOT NULL REFERENCES public.sja_forms(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  step_order int NOT NULL DEFAULT 1,
  operation text NOT NULL,
  hazard text NOT NULL,
  measure text NOT NULL,
  probability int CHECK (probability BETWEEN 1 AND 5),
  consequence int CHECK (consequence BETWEEN 1 AND 5),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (sja_id, step_order)
);

CREATE INDEX IF NOT EXISTS idx_hms_sja_steps_sja
  ON public.hms_sja_steps (sja_id, step_order);

CREATE TABLE IF NOT EXISTS public.hms_sja_signatures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sja_id uuid NOT NULL REFERENCES public.sja_forms(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  signed_at timestamptz NOT NULL DEFAULT now(),
  method public.hms_signature_method NOT NULL DEFAULT 'digital',
  signature_url text,
  pin_verified boolean NOT NULL DEFAULT false,
  device_info jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (sja_id, profile_id)
);

CREATE INDEX IF NOT EXISTS idx_hms_sja_signatures_sja
  ON public.hms_sja_signatures (sja_id, signed_at DESC);

CREATE TABLE IF NOT EXISTS public.hms_sja_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  department_id uuid REFERENCES public.departments(id) ON DELETE SET NULL,
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  source_sja_id uuid REFERENCES public.sja_forms(id) ON DELETE SET NULL,
  template_key text NOT NULL,
  title text NOT NULL,
  work_description text NOT NULL,
  location text,
  required_ppe text[] NOT NULL DEFAULT '{}',
  steps jsonb NOT NULL DEFAULT '[]'::jsonb,
  hazards jsonb NOT NULL DEFAULT '[]'::jsonb,
  measures jsonb NOT NULL DEFAULT '[]'::jsonb,
  active_window_hours int NOT NULL DEFAULT 8,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, template_key)
);

-- Offline-kø (Hive/Isar synker mot denne via Edge Function eller direkte RPC)
CREATE TABLE IF NOT EXISTS public.hms_offline_sync_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  entity_type text NOT NULL CHECK (entity_type IN ('ticket', 'risk_assessment', 'sja_form', 'sja_signature')),
  client_id uuid NOT NULL,
  operation text NOT NULL CHECK (operation IN ('insert', 'update', 'delete')),
  payload jsonb NOT NULL,
  status public.hms_sync_status NOT NULL DEFAULT 'pending',
  retry_count int NOT NULL DEFAULT 0,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  synced_at timestamptz,
  UNIQUE (user_id, entity_type, client_id, operation)
);

CREATE INDEX IF NOT EXISTS idx_hms_offline_sync_pending
  ON public.hms_offline_sync_queue (company_id, status, created_at)
  WHERE status IN ('pending', 'failed');

-- ── Seed: systemmaler (company_id NULL = alle bedrifter) ────────────────────

INSERT INTO public.hms_ticket_templates (
  company_id, template_key, title, description_template, category, severity, hms_domain, sort_order
)
SELECT v.company_id, v.template_key, v.title, v.description_template, v.category, v.severity, v.hms_domain, v.sort_order
FROM (VALUES
  (NULL::uuid, 'skade_kjoretoy', 'Skade på kjøretøy', 'Beskriv skade, registreringsnummer og om kjøretøyet er kjørbart.', 'Kjøretøy', 'middels'::public.ticket_severity, 'logistikk'::public.hms_domain, 10),
  (NULL::uuid, 'nestenulykke_lager', 'Nestenulykke på lager', 'Beskriv situasjonen, hva som nesten skjedde, og umiddelbare tiltak.', 'Nestenulykke', 'hoy'::public.ticket_severity, 'hms'::public.hms_domain, 20),
  (NULL::uuid, 'mangler_verneutstyr', 'Mangler verneutstyr', 'Hvilket verneutstyr mangler, og hvem er berørt?', 'Verneutstyr', 'middels'::public.ticket_severity, 'hms'::public.hms_domain, 30),
  (NULL::uuid, 'glatt_gulv', 'Glatt gulv / fallfare', 'Presiser sted, årsak (vann, olje, is) og om området er avsperret.', 'Fallfare', 'hoy'::public.ticket_severity, 'hms'::public.hms_domain, 40),
  (NULL::uuid, 'kvalitet_feillevering', 'Feillevering / skade på gods', 'Ordrenr, kunde og type skade på leveransen.', 'Kvalitet', 'middels'::public.ticket_severity, 'kvalitet'::public.hms_domain, 50)
) AS v(company_id, template_key, title, description_template, category, severity, hms_domain, sort_order)
WHERE NOT EXISTS (
  SELECT 1 FROM public.hms_ticket_templates t
  WHERE t.company_id IS NULL AND t.template_key = v.template_key
);

INSERT INTO public.hms_ros_templates (
  company_id, template_key, title, description, area, scenario_category,
  initial_probability, initial_consequence, existing_measures, proposed_measures, sort_order
)
SELECT v.company_id, v.template_key, v.title, v.description, v.area, v.scenario_category,
       v.initial_probability, v.initial_consequence, v.existing_measures, v.proposed_measures, v.sort_order
FROM (VALUES
  (NULL::uuid, 'tung_last', 'Håndtering av tung last', 'Løft, bæring og plassering av tungt gods', 'Lager / terminal', 'Manuelt løft',
   3, 4, 'Truck, team-løft, opplæring', 'Mekanisk hjelpemiddel, maks vekt per person', 10),
  (NULL::uuid, 'vanskelig_vaer', 'Kjøring under vanskelige værforhold', 'Glatt vei, snø, tåke, sterk vind', 'Transport', 'Kjøring',
   3, 5, 'Vinterdekk, fartsgrenser', 'Ruteomlegging, ekstra tid, varsling til kunde', 20),
  (NULL::uuid, 'glatt_gulv_ros', 'Glatt gulv / fall i terminal', 'Fall på glatt eller vått gulv', 'Terminal', 'Fallfare',
   4, 4, 'Rengjøring, skilt', 'Anti-skli, daglig inspeksjon, avsperring', 30)
) AS v(company_id, template_key, title, description, area, scenario_category,
       initial_probability, initial_consequence, existing_measures, proposed_measures, sort_order)
WHERE NOT EXISTS (
  SELECT 1 FROM public.hms_ros_templates t
  WHERE t.company_id IS NULL AND t.template_key = v.template_key
);

-- ── RLS ─────────────────────────────────────────────────────────────────────

ALTER TABLE public.hms_ticket_sensitive ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hms_ticket_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hms_ticket_leader_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hms_ros_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hms_ros_avvik_signals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hms_sja_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hms_sja_signatures ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hms_sja_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hms_offline_sync_queue ENABLE ROW LEVEL SECURITY;

-- Avvik (tickets) — strammet scope
DROP POLICY IF EXISTS tickets_select_scoped ON public.tickets;
DROP POLICY IF EXISTS tickets_insert_company ON public.tickets;
DROP POLICY IF EXISTS tickets_update_scoped ON public.tickets;
DROP POLICY IF EXISTS "tickets_select_scoped" ON public.tickets;
DROP POLICY IF EXISTS "tickets_update_scoped" ON public.tickets;

CREATE POLICY tickets_select_scoped ON public.tickets
  FOR SELECT TO authenticated
  USING (
    public.hms_can_access_record(company_id, department_id, reported_by)
    OR assigned_to = auth.uid()
  );

CREATE POLICY tickets_insert_company ON public.tickets
  FOR INSERT TO authenticated
  WITH CHECK (
    company_id = public.get_user_company_id()
    AND reported_by = auth.uid()
  );

CREATE POLICY tickets_update_scoped ON public.tickets
  FOR UPDATE TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      public.is_company_admin()
      OR reported_by = auth.uid()
      OR assigned_to = auth.uid()
      OR public.is_department_leader_of(department_id)
      OR (
        public.get_user_role() = 'leder'::public.user_role
        AND department_id IS NOT DISTINCT FROM public.get_user_department_id()
      )
    )
  )
  WITH CHECK (company_id = public.get_user_company_id());

-- Sensitive avvik
DROP POLICY IF EXISTS hms_ticket_sensitive_select ON public.hms_ticket_sensitive;
DROP POLICY IF EXISTS hms_ticket_sensitive_insert ON public.hms_ticket_sensitive;
DROP POLICY IF EXISTS hms_ticket_sensitive_update ON public.hms_ticket_sensitive;

CREATE POLICY hms_ticket_sensitive_select ON public.hms_ticket_sensitive
  FOR SELECT TO authenticated
  USING (public.hms_can_view_sensitive_ticket(ticket_id));

CREATE POLICY hms_ticket_sensitive_insert ON public.hms_ticket_sensitive
  FOR INSERT TO authenticated
  WITH CHECK (
    company_id = public.get_user_company_id()
    AND created_by = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.tickets t
      WHERE t.id = ticket_id
        AND t.reported_by = auth.uid()
    )
  );

CREATE POLICY hms_ticket_sensitive_update ON public.hms_ticket_sensitive
  FOR UPDATE TO authenticated
  USING (public.hms_can_view_sensitive_ticket(ticket_id))
  WITH CHECK (company_id = public.get_user_company_id());

-- Avviksmaler
DROP POLICY IF EXISTS hms_ticket_templates_select ON public.hms_ticket_templates;
CREATE POLICY hms_ticket_templates_select ON public.hms_ticket_templates
  FOR SELECT TO authenticated
  USING (
    company_id IS NULL
    OR company_id = public.get_user_company_id()
  );

DROP POLICY IF EXISTS hms_ticket_templates_manage ON public.hms_ticket_templates;
CREATE POLICY hms_ticket_templates_manage ON public.hms_ticket_templates
  FOR ALL TO authenticated
  USING (
    public.is_company_admin()
    AND company_id = public.get_user_company_id()
  )
  WITH CHECK (
    public.is_company_admin()
    AND company_id = public.get_user_company_id()
  );

-- Leder-tiltak på avvik
DROP POLICY IF EXISTS hms_ticket_leader_actions_select ON public.hms_ticket_leader_actions;
DROP POLICY IF EXISTS hms_ticket_leader_actions_insert ON public.hms_ticket_leader_actions;

CREATE POLICY hms_ticket_leader_actions_select ON public.hms_ticket_leader_actions
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.tickets t
      WHERE t.id = ticket_id
        AND (
          public.hms_can_access_record(t.company_id, t.department_id, t.reported_by)
          OR t.assigned_to = auth.uid()
        )
    )
  );

CREATE POLICY hms_ticket_leader_actions_insert ON public.hms_ticket_leader_actions
  FOR INSERT TO authenticated
  WITH CHECK (
    actor_id = auth.uid()
    AND company_id = public.get_user_company_id()
    AND EXISTS (
      SELECT 1 FROM public.tickets t
      WHERE t.id = ticket_id
        AND t.company_id = public.get_user_company_id()
        AND (
          public.is_company_admin()
          OR public.get_user_role() = 'leder'::public.user_role
          OR t.assigned_to = auth.uid()
        )
    )
  );

-- ROS
DROP POLICY IF EXISTS "Ansatte kan se risikoanalyser i sitt selskap" ON public.risk_assessments;
DROP POLICY IF EXISTS "Ledere kan opprette risikoanalyser" ON public.risk_assessments;
DROP POLICY IF EXISTS "Ledere kan oppdatere risikoanalyser" ON public.risk_assessments;
DROP POLICY IF EXISTS risk_assessments_select_scoped ON public.risk_assessments;
DROP POLICY IF EXISTS risk_assessments_insert_scoped ON public.risk_assessments;
DROP POLICY IF EXISTS risk_assessments_update_scoped ON public.risk_assessments;

CREATE POLICY risk_assessments_select_scoped ON public.risk_assessments
  FOR SELECT TO authenticated
  USING (public.hms_can_access_record(company_id, department_id, created_by));

CREATE POLICY risk_assessments_insert_scoped ON public.risk_assessments
  FOR INSERT TO authenticated
  WITH CHECK (
    company_id = public.get_user_company_id()
    AND created_by = auth.uid()
  );

CREATE POLICY risk_assessments_update_scoped ON public.risk_assessments
  FOR UPDATE TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      created_by = auth.uid()
      OR public.is_company_admin()
      OR public.get_user_role() = 'leder'::public.user_role
    )
  )
  WITH CHECK (company_id = public.get_user_company_id());

DROP POLICY IF EXISTS hms_ros_templates_select ON public.hms_ros_templates;
CREATE POLICY hms_ros_templates_select ON public.hms_ros_templates
  FOR SELECT TO authenticated
  USING (company_id IS NULL OR company_id = public.get_user_company_id());

DROP POLICY IF EXISTS hms_ros_templates_manage ON public.hms_ros_templates;
CREATE POLICY hms_ros_templates_manage ON public.hms_ros_templates
  FOR ALL TO authenticated
  USING (public.is_company_admin() AND company_id = public.get_user_company_id())
  WITH CHECK (public.is_company_admin() AND company_id = public.get_user_company_id());

DROP POLICY IF EXISTS hms_ros_avvik_signals_select ON public.hms_ros_avvik_signals;
DROP POLICY IF EXISTS hms_ros_avvik_signals_update ON public.hms_ros_avvik_signals;

CREATE POLICY hms_ros_avvik_signals_select ON public.hms_ros_avvik_signals
  FOR SELECT TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      public.is_company_admin()
      OR public.get_user_role() = 'leder'::public.user_role
    )
  );

CREATE POLICY hms_ros_avvik_signals_update ON public.hms_ros_avvik_signals
  FOR UPDATE TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      public.is_company_admin()
      OR public.get_user_role() = 'leder'::public.user_role
    )
  )
  WITH CHECK (company_id = public.get_user_company_id());

-- SJA
DROP POLICY IF EXISTS "Ansatte kan se SJA i sitt selskap" ON public.sja_forms;
DROP POLICY IF EXISTS "Alle kan opprette SJA" ON public.sja_forms;
DROP POLICY IF EXISTS "Opprettere og ledere kan oppdatere SJA" ON public.sja_forms;
DROP POLICY IF EXISTS sja_forms_select_scoped ON public.sja_forms;
DROP POLICY IF EXISTS sja_forms_insert_scoped ON public.sja_forms;
DROP POLICY IF EXISTS sja_forms_update_scoped ON public.sja_forms;

CREATE POLICY sja_forms_select_scoped ON public.sja_forms
  FOR SELECT TO authenticated
  USING (public.hms_can_access_record(company_id, department_id, created_by));

CREATE POLICY sja_forms_insert_scoped ON public.sja_forms
  FOR INSERT TO authenticated
  WITH CHECK (
    company_id = public.get_user_company_id()
    AND created_by = auth.uid()
  );

CREATE POLICY sja_forms_update_scoped ON public.sja_forms
  FOR UPDATE TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      created_by = auth.uid()
      OR public.is_company_admin()
      OR public.get_user_role() = 'leder'::public.user_role
    )
  )
  WITH CHECK (company_id = public.get_user_company_id());

DROP POLICY IF EXISTS hms_sja_steps_select ON public.hms_sja_steps;
DROP POLICY IF EXISTS hms_sja_steps_mutate ON public.hms_sja_steps;

CREATE POLICY hms_sja_steps_select ON public.hms_sja_steps
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.sja_forms s
      WHERE s.id = sja_id
        AND public.hms_can_access_record(s.company_id, s.department_id, s.created_by)
    )
  );

CREATE POLICY hms_sja_steps_mutate ON public.hms_sja_steps
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.sja_forms s
      WHERE s.id = sja_id
        AND s.company_id = public.get_user_company_id()
        AND (
          s.created_by = auth.uid()
          OR public.is_company_admin()
          OR public.get_user_role() = 'leder'::public.user_role
        )
    )
  )
  WITH CHECK (company_id = public.get_user_company_id());

DROP POLICY IF EXISTS hms_sja_signatures_select ON public.hms_sja_signatures;
DROP POLICY IF EXISTS hms_sja_signatures_insert ON public.hms_sja_signatures;

CREATE POLICY hms_sja_signatures_select ON public.hms_sja_signatures
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.sja_forms s
      WHERE s.id = sja_id
        AND public.hms_can_access_record(s.company_id, s.department_id, s.created_by)
    )
  );

CREATE POLICY hms_sja_signatures_insert ON public.hms_sja_signatures
  FOR INSERT TO authenticated
  WITH CHECK (
    profile_id = auth.uid()
    AND company_id = public.get_user_company_id()
    AND EXISTS (
      SELECT 1 FROM public.sja_forms s
      WHERE s.id = sja_id
        AND s.company_id = public.get_user_company_id()
    )
  );

DROP POLICY IF EXISTS hms_sja_templates_select ON public.hms_sja_templates;
DROP POLICY IF EXISTS hms_sja_templates_mutate ON public.hms_sja_templates;

CREATE POLICY hms_sja_templates_select ON public.hms_sja_templates
  FOR SELECT TO authenticated
  USING (company_id = public.get_user_company_id());

CREATE POLICY hms_sja_templates_mutate ON public.hms_sja_templates
  FOR ALL TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      created_by = auth.uid()
      OR public.is_company_admin()
      OR public.get_user_role() = 'leder'::public.user_role
    )
  )
  WITH CHECK (company_id = public.get_user_company_id());

-- Offline-kø: kun egen bruker
DROP POLICY IF EXISTS hms_offline_sync_queue_own ON public.hms_offline_sync_queue;

CREATE POLICY hms_offline_sync_queue_own ON public.hms_offline_sync_queue
  FOR ALL TO authenticated
  USING (user_id = auth.uid() AND company_id = public.get_user_company_id())
  WITH CHECK (user_id = auth.uid() AND company_id = public.get_user_company_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.hms_ticket_sensitive TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.hms_ticket_templates TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.hms_ticket_leader_actions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.hms_ros_templates TO authenticated;
GRANT SELECT, UPDATE ON public.hms_ros_avvik_signals TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.hms_sja_steps TO authenticated;
GRANT SELECT, INSERT ON public.hms_sja_signatures TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.hms_sja_templates TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.hms_offline_sync_queue TO authenticated;
