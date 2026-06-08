-- Permanente sporings-ID-er for avvik/HMS og Bot/Trekk — beholdes ved soft-slett.

-- ── Felles hjelpefunksjoner ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.case_trace_code(p_id UUID)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT upper(left(replace(p_id::text, '-', ''), 8));
$$;

CREATE OR REPLACE FUNCTION public.ticket_trace_prefix(p_hms_domain TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(coalesce(p_hms_domain, 'hms'))
    WHEN 'kvalitet' THEN 'KVA'
    WHEN 'logistikk' THEN 'LOG'
    WHEN 'hms' THEN 'HMS'
    ELSE 'AVV'
  END;
$$;

-- ── Bot/Trekk: trace_ref = case_number (aldri gjenbrukes) ─────────────────────

ALTER TABLE public.partner_deduction_cases
  ADD COLUMN IF NOT EXISTS trace_ref TEXT;

UPDATE public.partner_deduction_cases
SET trace_ref = case_number
WHERE trace_ref IS NULL OR trace_ref = '';

ALTER TABLE public.partner_deduction_cases
  ALTER COLUMN trace_ref SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_partner_deduction_cases_trace_ref
  ON public.partner_deduction_cases (company_id, trace_ref);

CREATE OR REPLACE FUNCTION public.next_partner_deduction_case_number(p_company_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_max INT;
  v_seq INT;
BEGIN
  PERFORM pg_advisory_xact_lock(
    hashtext('partner_deduction_case_num:' || p_company_id::text || ':' || v_year)
  );

  SELECT coalesce(max(
    NULLIF(regexp_replace(case_number, '^BOT-' || v_year || '-', ''), '')::INT
  ), 0) INTO v_max
  FROM public.partner_deduction_cases
  WHERE company_id = p_company_id
    AND case_number LIKE 'BOT-' || v_year || '-%';

  v_seq := v_max + 1;
  RETURN 'BOT-' || v_year || '-' || lpad(v_seq::TEXT, 4, '0');
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_deduction_set_trace_ref()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.trace_ref := NEW.case_number;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_partner_deduction_set_trace_ref ON public.partner_deduction_cases;
CREATE TRIGGER trg_partner_deduction_set_trace_ref
  BEFORE INSERT OR UPDATE OF case_number ON public.partner_deduction_cases
  FOR EACH ROW
  EXECUTE FUNCTION public.partner_deduction_set_trace_ref();

-- ── Avvik/HMS: trace_ref + soft-slett ───────────────────────────────────────

ALTER TABLE public.tickets
  ADD COLUMN IF NOT EXISTS trace_ref TEXT,
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS deletion_comment TEXT;

CREATE OR REPLACE FUNCTION public.next_ticket_trace_ref(
  p_company_id UUID,
  p_hms_domain TEXT DEFAULT 'hms'
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_prefix TEXT := public.ticket_trace_prefix(p_hms_domain);
  v_max INT;
  v_seq INT;
BEGIN
  PERFORM pg_advisory_xact_lock(
    hashtext('ticket_trace_ref:' || p_company_id::text || ':' || v_prefix || ':' || v_year)
  );

  SELECT coalesce(max(
    NULLIF(regexp_replace(trace_ref, '^' || v_prefix || '-' || v_year || '-', ''), '')::INT
  ), 0) INTO v_max
  FROM public.tickets
  WHERE company_id = p_company_id
    AND trace_ref LIKE v_prefix || '-' || v_year || '-%';

  v_seq := v_max + 1;
  RETURN v_prefix || '-' || v_year || '-' || lpad(v_seq::TEXT, 4, '0');
END;
$$;

CREATE OR REPLACE FUNCTION public.tickets_set_trace_ref()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.trace_ref IS NULL OR trim(NEW.trace_ref) = '' THEN
    NEW.trace_ref := public.next_ticket_trace_ref(
      NEW.company_id,
      NEW.hms_domain::text
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tickets_set_trace_ref ON public.tickets;
CREATE TRIGGER trg_tickets_set_trace_ref
  BEFORE INSERT ON public.tickets
  FOR EACH ROW
  EXECUTE FUNCTION public.tickets_set_trace_ref();

-- Backfill eksisterende avvik (per bedrift, domene, år — kronologisk)
DO $$
DECLARE
  rec RECORD;
  v_year TEXT;
  v_prefix TEXT;
  v_seq INT;
BEGIN
  FOR rec IN
    SELECT id, company_id, hms_domain::text AS domain, created_at
    FROM public.tickets
    WHERE trace_ref IS NULL OR trim(trace_ref) = ''
    ORDER BY company_id, hms_domain, created_at, id
  LOOP
    v_year := to_char(coalesce(rec.created_at, now()), 'YYYY');
    v_prefix := public.ticket_trace_prefix(rec.domain);

    SELECT coalesce(max(
      NULLIF(regexp_replace(trace_ref, '^' || v_prefix || '-' || v_year || '-', ''), '')::INT
    ), 0) + 1 INTO v_seq
    FROM public.tickets
    WHERE company_id = rec.company_id
      AND trace_ref LIKE v_prefix || '-' || v_year || '-%';

    UPDATE public.tickets
    SET trace_ref = v_prefix || '-' || v_year || '-' || lpad(v_seq::TEXT, 4, '0')
    WHERE id = rec.id;
  END LOOP;
END;
$$;

ALTER TABLE public.tickets
  ALTER COLUMN trace_ref SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_tickets_trace_ref
  ON public.tickets (company_id, trace_ref);

CREATE INDEX IF NOT EXISTS idx_tickets_deleted_at
  ON public.tickets (company_id, deleted_at)
  WHERE deleted_at IS NOT NULL;

CREATE OR REPLACE FUNCTION public.ticket_public_ref(p_ticket_number INTEGER)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_ticket_number IS NULL THEN 'Avvik'
    ELSE 'Avvik #' || p_ticket_number::text
  END;
$$;

CREATE OR REPLACE FUNCTION public.ticket_display_ref(
  p_trace_ref TEXT DEFAULT NULL,
  p_ticket_number INTEGER DEFAULT NULL
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN nullif(trim(p_trace_ref), '') IS NOT NULL THEN trim(p_trace_ref)
    ELSE public.ticket_public_ref(p_ticket_number)
  END;
$$;

-- Oppdater varsel-triggere til å bruke trace_ref
CREATE OR REPLACE FUNCTION public.notify_leaders_on_ticket()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  dept_id uuid;
  reporter_name text;
  assignee_phone text;
  assignee_email text;
  assignee_name text;
  sms_body text;
  ref text;
BEGIN
  ref := public.ticket_display_ref(new.trace_ref, new.ticket_number);

  SELECT coalesce(full_name, 'Ansatt') INTO reporter_name
  FROM public.profiles WHERE id = new.reported_by;

  dept_id := coalesce(
    new.department_id,
    (SELECT department_id FROM public.profiles WHERE id = new.reported_by)
  );

  IF new.assigned_to IS NOT NULL THEN
    SELECT
      coalesce(full_name, 'Saksbehandler'),
      phone,
      email
    INTO assignee_name, assignee_phone, assignee_email
    FROM public.profiles
    WHERE id = new.assigned_to;

    sms_body :=
      'DriftPro: ' || ref || ' til deg. «'
      || left(coalesce(new.title, 'Uten tittel'), 50)
      || '». Alvor: ' || coalesce(new.severity::text, 'middels')
      || '. Fra: ' || reporter_name
      || '. Logg inn og behandle saken.';

    IF coalesce(assignee_phone, '') <> '' THEN
      PERFORM public.queue_sms_if_allowed(
        new.company_id, new.assigned_to, assignee_phone,
        sms_body, 'ticket_assigned', 'tickets', new.id,
        'ticket_assigned', 'Avvik tildelt saksbehandler', false
      );
    END IF;

    IF coalesce(assignee_email, '') <> '' THEN
      PERFORM public.queue_email_if_allowed(
        new.company_id, new.assigned_to, assignee_email,
        ref || ' — handling kreves',
        'Du er valgt som saksbehandler.' || E'\n\n'
          || ref || E'\n'
          || 'Tittel: ' || coalesce(new.title, 'uten tittel') || E'\n'
          || 'Alvorlighet: ' || coalesce(new.severity::text, 'middels') || E'\n'
          || 'Fra: ' || reporter_name,
        'ticket_assigned', 'tickets', new.id,
        'ticket_assigned', 'Avvik tildelt (e-post)', false
      );
    END IF;

    RETURN new;
  END IF;

  FOR rec IN
    SELECT id, email
    FROM public.profiles
    WHERE company_id = new.company_id
      AND is_active = true
      AND is_approved = true
      AND partner_id IS NULL
      AND role <> 'samarbeidspartner'::public.user_role
  LOOP
    IF NOT public.profile_receives_for_department(
      new.company_id, rec.id, dept_id, 'ticket_new'
    ) THEN
      CONTINUE;
    END IF;

    PERFORM public.queue_email_if_allowed(
      new.company_id,
      rec.id,
      rec.email,
      ref || ' registrert',
      'Tittel: ' || coalesce(new.title, 'uten tittel') || E'\nAlvorlighet: ' || coalesce(new.severity::text, 'middels'),
      'ticket',
      'tickets',
      new.id,
      'ticket_new',
      'Nytt avvik → avdeling (e-post)',
      false
    );
  END LOOP;

  RETURN new;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_ticket_status_sms()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _phone text;
  _msg text;
  _resolver text;
  _status_no text;
  _ref text;
BEGIN
  IF tg_op <> 'UPDATE' THEN
    RETURN new;
  END IF;

  IF old.status IS NOT DISTINCT FROM new.status
     AND old.resolution_comment IS NOT DISTINCT FROM new.resolution_comment THEN
    RETURN new;
  END IF;

  _ref := public.ticket_display_ref(new.trace_ref, new.ticket_number);

  SELECT coalesce(full_name, 'Leder') INTO _resolver
  FROM public.profiles
  WHERE id = coalesce(new.resolved_by, auth.uid());

  _status_no := CASE new.status::text
    WHEN 'aapen' THEN 'åpen'
    WHEN 'under_behandling' THEN 'under arbeid'
    WHEN 'tiltak_utfort' THEN 'tiltak utført'
    WHEN 'lukket' THEN 'ferdig behandlet'
    ELSE new.status::text
  END;

  IF new.status IN ('tiltak_utfort', 'lukket')
     AND old.status IS DISTINCT FROM new.status THEN
    SELECT phone INTO _phone FROM public.profiles WHERE id = new.reported_by;

    _msg :=
      'DriftPro: ' || _ref || ' «' || left(coalesce(new.title, ''), 40) || '» '
      || 'er ' || _status_no || '. '
      || 'Av: ' || _resolver || '.';

    IF coalesce(new.resolution_comment, '') <> '' THEN
      _msg := _msg || ' ' || left(new.resolution_comment, 120);
    END IF;

    IF coalesce(_phone, '') <> '' THEN
      PERFORM public.queue_sms_if_allowed(
        new.company_id,
        new.reported_by,
        _phone,
        _msg,
        'ticket_resolved',
        'tickets',
        new.id,
        'ticket_status',
        'Avvik ferdig behandlet',
        false
      );
    END IF;
  ELSIF old.status IS DISTINCT FROM new.status THEN
    SELECT phone INTO _phone FROM public.profiles WHERE id = new.reported_by;

    _msg :=
      'DriftPro: ' || _ref || ' «' || left(coalesce(new.title, ''), 40) || '» '
      || 'har status «' || _status_no || '».';

    IF coalesce(_phone, '') <> '' THEN
      PERFORM public.queue_sms_if_allowed(
        new.company_id,
        new.reported_by,
        _phone,
        _msg,
        'ticket_status',
        'tickets',
        new.id,
        'ticket_status',
        'Avvik statusendring',
        false
      );
    END IF;
  END IF;

  IF new.severity IN ('hoy', 'kritisk')
     AND new.status = 'aapen'
     AND new.assigned_to IS NOT NULL
     AND (old.severity IS DISTINCT FROM new.severity OR old.status IS DISTINCT FROM new.status) THEN
    SELECT phone INTO _phone FROM public.profiles WHERE id = new.assigned_to;
    IF coalesce(_phone, '') <> '' THEN
      PERFORM public.queue_sms_if_allowed(
        new.company_id,
        new.assigned_to,
        _phone,
        'DriftPro KRITISK ' || _ref || ': ' || coalesce(new.title, 'Uten tittel'),
        'ticket_critical',
        'tickets',
        new.id,
        'ticket_assigned',
        'Kritisk avvik',
        false
      );
    END IF;
  END IF;

  RETURN new;
END;
$$;

CREATE OR REPLACE FUNCTION public.soft_delete_ticket(
  p_ticket_id UUID,
  p_deletion_comment TEXT
)
RETURNS public.tickets
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ticket public.tickets%ROWTYPE;
  v_role public.user_role;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  v_role := public.get_user_role();
  IF v_role NOT IN ('admin', 'superadmin') THEN
    RAISE EXCEPTION 'Kun admin kan slette avvik';
  END IF;

  IF coalesce(trim(p_deletion_comment), '') = '' THEN
    RAISE EXCEPTION 'Du må skrive en kommentar ved sletting';
  END IF;

  SELECT * INTO v_ticket FROM public.tickets WHERE id = p_ticket_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Avvik ikke funnet';
  END IF;

  IF v_ticket.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Avviket er allerede slettet';
  END IF;

  UPDATE public.tickets
  SET deleted_at = now(),
      deleted_by = auth.uid(),
      deletion_comment = trim(p_deletion_comment),
      status = 'lukket'::public.ticket_status,
      updated_at = now()
  WHERE id = p_ticket_id
  RETURNING * INTO v_ticket;

  RETURN v_ticket;
END;
$$;

CREATE OR REPLACE FUNCTION public.lookup_case_trace(
  p_company_id UUID,
  p_query TEXT,
  p_limit INT DEFAULT 20
)
RETURNS TABLE (
  source TEXT,
  id UUID,
  trace_ref TEXT,
  trace_code TEXT,
  title TEXT,
  status TEXT,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH q AS (
    SELECT lower(trim(coalesce(p_query, ''))) AS raw
  )
  SELECT * FROM (
    SELECT
      'ticket'::text AS source,
      t.id,
      t.trace_ref,
      public.case_trace_code(t.id) AS trace_code,
      t.title,
      t.status::text,
      t.deleted_at,
      t.created_at
    FROM public.tickets t, q
    WHERE t.company_id = p_company_id
      AND q.raw <> ''
      AND (
        lower(t.trace_ref) LIKE '%' || q.raw || '%'
        OR public.case_trace_code(t.id) = upper(replace(q.raw, '-', ''))
        OR t.id::text = q.raw
        OR (q.raw ~ '^\d+$' AND t.ticket_number::text = q.raw)
      )

    UNION ALL

    SELECT
      'partner_deduction'::text AS source,
      c.id,
      c.trace_ref,
      public.case_trace_code(c.id) AS trace_code,
      c.template_title AS title,
      c.status,
      c.deleted_at,
      c.created_at
    FROM public.partner_deduction_cases c, q
    WHERE c.company_id = p_company_id
      AND q.raw <> ''
      AND (
        lower(c.trace_ref) LIKE '%' || q.raw || '%'
        OR lower(c.case_number) LIKE '%' || q.raw || '%'
        OR public.case_trace_code(c.id) = upper(replace(q.raw, '-', ''))
        OR c.id::text = q.raw
        OR lower(coalesce(c.logiqrma_case_number, '')) LIKE '%' || q.raw || '%'
        OR lower(coalesce(c.voucher_number, '')) LIKE '%' || q.raw || '%'
      )
  ) hits
  ORDER BY created_at DESC
  LIMIT greatest(coalesce(p_limit, 20), 1);
$$;

-- Oppdater Bot/Trekk insert
CREATE OR REPLACE FUNCTION public.create_partner_deduction_case(
  p_company_id UUID,
  p_partner_id UUID,
  p_template_id TEXT,
  p_template_title TEXT,
  p_short_description TEXT,
  p_comment TEXT DEFAULT NULL,
  p_amount_nok NUMERIC DEFAULT 500,
  p_notify_sms BOOLEAN DEFAULT false,
  p_notify_email BOOLEAN DEFAULT false,
  p_sms_body TEXT DEFAULT NULL,
  p_email_subject TEXT DEFAULT NULL,
  p_email_body TEXT DEFAULT NULL,
  p_logiqrma_case_number TEXT DEFAULT NULL,
  p_voucher_number TEXT DEFAULT NULL,
  p_logistics_description TEXT DEFAULT NULL
)
RETURNS public.partner_deduction_cases
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.partner_deduction_cases%ROWTYPE;
  v_case_number TEXT;
  v_partner public.partners%ROWTYPE;
  v_phone TEXT;
  v_email TEXT;
  v_amount NUMERIC(12, 2);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND company_id = p_company_id
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang til bedrift';
  END IF;

  SELECT * INTO v_partner FROM public.partners
  WHERE id = p_partner_id AND company_id = p_company_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Partner ikke funnet';
  END IF;

  v_amount := coalesce(p_amount_nok, 500);
  IF v_amount < 0 THEN
    RAISE EXCEPTION 'Beløp kan ikke være negativt';
  END IF;

  v_case_number := public.next_partner_deduction_case_number(p_company_id);

  INSERT INTO public.partner_deduction_cases (
    company_id, partner_id, case_number, trace_ref,
    template_id, template_title, short_description, comment,
    amount_nok, status, created_by,
    notification_sms_body, notification_email_subject, notification_email_body,
    logiqrma_case_number, voucher_number, logistics_description
  ) VALUES (
    p_company_id, p_partner_id, v_case_number, v_case_number,
    p_template_id, p_template_title, p_short_description, nullif(trim(p_comment), ''),
    v_amount, 'registered', auth.uid(),
    p_sms_body, p_email_subject, p_email_body,
    nullif(trim(p_logiqrma_case_number), ''),
    nullif(trim(p_voucher_number), ''),
    nullif(trim(p_logistics_description), '')
  )
  RETURNING * INTO v_row;

  v_phone := nullif(trim(v_partner.phone), '');
  v_email := nullif(trim(v_partner.email), '');

  IF p_notify_sms AND v_phone IS NOT NULL AND coalesce(p_sms_body, '') <> '' THEN
    PERFORM public.queue_sms_if_allowed(
      p_company_id, NULL, v_phone, replace(p_sms_body, '{sak}', v_case_number),
      'partner_deduction', 'partner_deduction_cases', v_row.id,
      'partner_compose', 'Bot/trekk varslet via SMS', true
    );
    UPDATE public.partner_deduction_cases
    SET sms_sent = true, notified_at = coalesce(notified_at, now()),
        status = CASE WHEN status = 'registered' THEN 'notified' ELSE status END
    WHERE id = v_row.id
    RETURNING * INTO v_row;
  END IF;

  IF p_notify_email AND v_email IS NOT NULL
     AND coalesce(p_email_subject, '') <> ''
     AND coalesce(p_email_body, '') <> '' THEN
    PERFORM public.queue_email_if_allowed(
      p_company_id, NULL, v_email,
      replace(p_email_subject, '{sak}', v_case_number),
      replace(p_email_body, '{sak}', v_case_number),
      'partner_deduction', 'partner_deduction_cases', v_row.id,
      'partner_compose', 'Bot/trekk varslet via e-post', true
    );
    UPDATE public.partner_deduction_cases
    SET email_sent = true, notified_at = coalesce(notified_at, now()),
        status = CASE WHEN status = 'registered' THEN 'notified' ELSE status END
    WHERE id = v_row.id
    RETURNING * INTO v_row;
  END IF;

  RETURN v_row;
END;
$$;

DROP FUNCTION IF EXISTS public.list_partner_deduction_cases(UUID, TEXT, UUID, INT, INT);

CREATE OR REPLACE FUNCTION public.list_partner_deduction_cases(
  p_company_id UUID,
  p_status TEXT DEFAULT NULL,
  p_partner_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 200,
  p_offset INT DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  company_id UUID,
  partner_id UUID,
  partner_name TEXT,
  case_number TEXT,
  trace_ref TEXT,
  trace_code TEXT,
  template_id TEXT,
  template_title TEXT,
  short_description TEXT,
  comment TEXT,
  amount_nok NUMERIC,
  status TEXT,
  created_by UUID,
  created_by_name TEXT,
  created_at TIMESTAMPTZ,
  notified_at TIMESTAMPTZ,
  sms_sent BOOLEAN,
  email_sent BOOLEAN,
  invoiced_at TIMESTAMPTZ,
  invoiced_by UUID,
  invoiced_by_name TEXT,
  evidence_count BIGINT,
  logiqrma_case_number TEXT,
  voucher_number TEXT,
  logistics_description TEXT,
  is_locked BOOLEAN,
  locked_at TIMESTAMPTZ,
  unlocked_at TIMESTAMPTZ,
  unlocked_by_name TEXT,
  deleted_at TIMESTAMPTZ,
  deleted_by_name TEXT,
  deletion_comment TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.id, c.company_id, c.partner_id, p.name AS partner_name,
    c.case_number, c.trace_ref, public.case_trace_code(c.id) AS trace_code,
    c.template_id, c.template_title, c.short_description, c.comment,
    c.amount_nok, c.status, c.created_by,
    cr.full_name AS created_by_name,
    c.created_at, c.notified_at, c.sms_sent, c.email_sent,
    c.invoiced_at, c.invoiced_by, inv.full_name AS invoiced_by_name,
    (SELECT count(*) FROM public.partner_deduction_evidence e WHERE e.case_id = c.id) AS evidence_count,
    c.logiqrma_case_number, c.voucher_number, c.logistics_description,
    c.is_locked, c.locked_at, c.unlocked_at, unl.full_name AS unlocked_by_name,
    c.deleted_at, del.full_name AS deleted_by_name, c.deletion_comment
  FROM public.partner_deduction_cases c
  JOIN public.partners p ON p.id = c.partner_id
  LEFT JOIN public.profiles cr ON cr.id = c.created_by
  LEFT JOIN public.profiles inv ON inv.id = c.invoiced_by
  LEFT JOIN public.profiles unl ON unl.id = c.unlocked_by
  LEFT JOIN public.profiles del ON del.id = c.deleted_by
  WHERE c.company_id = p_company_id
    AND EXISTS (
      SELECT 1 FROM public.profiles pr
      WHERE pr.id = auth.uid() AND pr.company_id = p_company_id
    )
    AND (p_status IS NULL OR c.status = p_status)
    AND (p_partner_id IS NULL OR c.partner_id = p_partner_id)
  ORDER BY c.created_at DESC
  LIMIT greatest(p_limit, 1)
  OFFSET greatest(p_offset, 0);
$$;

GRANT EXECUTE ON FUNCTION public.case_trace_code(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.next_ticket_trace_ref(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.soft_delete_ticket(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.lookup_case_trace(UUID, TEXT, INT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_partner_deduction_case TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_partner_deduction_cases(UUID, TEXT, UUID, INT, INT) TO authenticated, service_role;
