-- HMS oppfølging: mail/push til valgte mottakere, frist, påminnelse dagen før,
-- lukkes av involvert (stopper da purring). Gjelder avvik, vernerunde, SJA, ROS m.fl.

CREATE TABLE IF NOT EXISTS public.hms_follow_ups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  module TEXT NOT NULL,
  reference_type TEXT NOT NULL,
  reference_id UUID NOT NULL,
  title TEXT NOT NULL,
  summary TEXT,
  deviation_count INT NOT NULL DEFAULT 1,
  follow_up_due_at DATE,
  status TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'closed')),
  closed_at TIMESTAMPTZ,
  closed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  close_notes TEXT,
  send_email BOOLEAN NOT NULL DEFAULT true,
  send_push BOOLEAN NOT NULL DEFAULT true,
  last_reminder_on DATE,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hms_follow_ups_company_status
  ON public.hms_follow_ups (company_id, status, follow_up_due_at);

CREATE INDEX IF NOT EXISTS idx_hms_follow_ups_ref
  ON public.hms_follow_ups (reference_type, reference_id);

CREATE TABLE IF NOT EXISTS public.hms_follow_up_recipients (
  follow_up_id UUID NOT NULL REFERENCES public.hms_follow_ups(id) ON DELETE CASCADE,
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  PRIMARY KEY (follow_up_id, profile_id)
);

CREATE INDEX IF NOT EXISTS idx_hms_follow_up_recipients_profile
  ON public.hms_follow_up_recipients (profile_id);

ALTER TABLE public.hms_follow_ups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hms_follow_up_recipients ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS hms_follow_ups_select ON public.hms_follow_ups;
CREATE POLICY hms_follow_ups_select ON public.hms_follow_ups
  FOR SELECT TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      public.is_company_admin()
      OR created_by = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.hms_follow_up_recipients r
        WHERE r.follow_up_id = id AND r.profile_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS hms_follow_ups_insert ON public.hms_follow_ups;
CREATE POLICY hms_follow_ups_insert ON public.hms_follow_ups
  FOR INSERT TO authenticated
  WITH CHECK (company_id = public.get_user_company_id());

DROP POLICY IF EXISTS hms_follow_ups_update ON public.hms_follow_ups;
CREATE POLICY hms_follow_ups_update ON public.hms_follow_ups
  FOR UPDATE TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      public.is_company_admin()
      OR created_by = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.hms_follow_up_recipients r
        WHERE r.follow_up_id = id AND r.profile_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS hms_follow_up_recipients_select ON public.hms_follow_up_recipients;
CREATE POLICY hms_follow_up_recipients_select ON public.hms_follow_up_recipients
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.hms_follow_ups f
      WHERE f.id = follow_up_id
        AND f.company_id = public.get_user_company_id()
    )
  );

DROP POLICY IF EXISTS hms_follow_up_recipients_insert ON public.hms_follow_up_recipients;
CREATE POLICY hms_follow_up_recipients_insert ON public.hms_follow_up_recipients
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.hms_follow_ups f
      WHERE f.id = follow_up_id
        AND f.company_id = public.get_user_company_id()
    )
  );

CREATE OR REPLACE FUNCTION public.hms_module_label(p_module TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(coalesce(p_module, ''))
    WHEN 'ticket' THEN 'avvik'
    WHEN 'safety_round' THEN 'vernerunde'
    WHEN 'sja' THEN 'SJA'
    WHEN 'risk_assessment' THEN 'risikoanalyse'
    WHEN 'equipment' THEN 'utstyr'
    WHEN 'competence' THEN 'kompetanse'
    ELSE coalesce(nullif(p_module, ''), 'HMS')
  END;
$$;

CREATE OR REPLACE FUNCTION public.hms_create_follow_up_notify(
  p_company_id UUID,
  p_module TEXT,
  p_reference_type TEXT,
  p_reference_id UUID,
  p_title TEXT,
  p_summary TEXT DEFAULT NULL,
  p_deviation_count INT DEFAULT 1,
  p_due_at DATE DEFAULT NULL,
  p_recipient_ids UUID[] DEFAULT '{}',
  p_send_email BOOLEAN DEFAULT true,
  p_send_push BOOLEAN DEFAULT true
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_uid UUID;
  v_creator TEXT;
  v_module_label TEXT;
  v_due TEXT;
  v_count INT;
  v_subject TEXT;
  v_push_body TEXT;
  v_body TEXT;
  v_html TEXT;
  v_email TEXT;
  v_name TEXT;
  v_rec UUID;
BEGIN
  IF p_company_id IS NULL OR p_company_id IS DISTINCT FROM public.get_user_company_id() THEN
    IF NOT public.is_company_admin() AND auth.role() <> 'service_role' THEN
      RAISE EXCEPTION 'Ingen tilgang';
    END IF;
  END IF;

  IF p_recipient_ids IS NULL OR cardinality(p_recipient_ids) = 0 THEN
    RAISE EXCEPTION 'Velg minst én mottaker';
  END IF;

  IF NOT coalesce(p_send_email, false) AND NOT coalesce(p_send_push, false) THEN
    RAISE EXCEPTION 'Velg e-post og/eller push';
  END IF;

  v_uid := auth.uid();
  SELECT coalesce(full_name, 'Kollega') INTO v_creator
  FROM public.profiles WHERE id = v_uid;

  v_module_label := public.hms_module_label(p_module);
  v_count := greatest(coalesce(p_deviation_count, 1), 1);
  v_due := public.format_nb_date(p_due_at);

  INSERT INTO public.hms_follow_ups (
    company_id, module, reference_type, reference_id,
    title, summary, deviation_count, follow_up_due_at,
    send_email, send_push, created_by
  ) VALUES (
    p_company_id, p_module, p_reference_type, p_reference_id,
    coalesce(nullif(trim(p_title), ''), 'HMS-oppfølging'),
    nullif(trim(p_summary), ''),
    v_count,
    p_due_at,
    coalesce(p_send_email, true),
    coalesce(p_send_push, true),
    v_uid
  )
  RETURNING id INTO v_id;

  INSERT INTO public.hms_follow_up_recipients (follow_up_id, profile_id)
  SELECT DISTINCT v_id, x
  FROM unnest(p_recipient_ids) AS x
  WHERE x IS NOT NULL
  ON CONFLICT DO NOTHING;

  -- Oppdater ticket due_date når satt
  IF p_module = 'ticket' AND p_due_at IS NOT NULL THEN
    UPDATE public.tickets
    SET due_date = p_due_at,
        updated_at = now()
    WHERE id = p_reference_id
      AND company_id = p_company_id
      AND status <> 'lukket'::public.ticket_status;
  END IF;

  FOR v_rec IN
    SELECT DISTINCT profile_id FROM public.hms_follow_up_recipients WHERE follow_up_id = v_id
  LOOP
    SELECT coalesce(full_name, 'Kollega'), email
    INTO v_name, v_email
    FROM public.profiles WHERE id = v_rec;

    IF v_count > 1 THEN
      v_subject := format(
        'DriftPro: %s avvik/punkter til oppfølging — %s',
        v_count,
        left(coalesce(p_title, v_module_label), 60)
      );
      v_push_body := format(
        '%s har sendt deg %s punkter i %s%s. Åpne DriftPro og følg opp.',
        v_creator,
        v_count,
        v_module_label,
        CASE WHEN v_due IS NOT NULL THEN format(' (frist %s)', v_due) ELSE '' END
      );
    ELSE
      v_subject := format(
        'DriftPro: %s sendt til deg — %s',
        initcap(v_module_label),
        left(coalesce(p_title, 'uten tittel'), 60)
      );
      v_push_body := format(
        '%s har sendt deg et %s%s. Følg opp i DriftPro.',
        v_creator,
        v_module_label,
        CASE WHEN v_due IS NOT NULL THEN format(' med frist %s', v_due) ELSE '' END
      );
    END IF;

    v_body := format(
      E'Hei %s,\n\n'
      || '%s har sendt deg %s til oppfølging i DriftPro.\n\n'
      || 'Modul: %s\n'
      || 'Tittel: %s\n'
      || CASE WHEN v_count > 1 THEN format('Antall punkter/avvik: %s\n', v_count) ELSE '' END
      || CASE WHEN v_due IS NOT NULL THEN format('Oppfølgingsfrist: %s\n', v_due) ELSE '' END
      || CASE WHEN nullif(trim(p_summary), '') IS NOT NULL
           THEN format(E'\nOppsummering:\n%s\n', trim(p_summary))
           ELSE '' END
      || E'\nLogg inn og lukk oppfølgingen når tiltak er utført — da stopper påminnelser.\n'
      || 'https://driftpro.no\n',
      v_name,
      v_creator,
      CASE WHEN v_count > 1 THEN format('%s avvik/punkter', v_count) ELSE format('et %s', v_module_label) END,
      v_module_label,
      coalesce(p_title, '—')
    );

    BEGIN
      v_html := public.build_driftpro_email_html(
        format('Oppfølging · %s', v_module_label),
        CASE
          WHEN v_count > 1 THEN format(
            '%s har sendt deg %s punkter som må følges opp.',
            v_creator, v_count
          )
          ELSE format('%s har sendt deg et %s til oppfølging.', v_creator, v_module_label)
        END,
        (
          SELECT coalesce(jsonb_agg(elem), '[]'::jsonb)
          FROM (
            SELECT jsonb_build_object('label', 'Modul', 'value', v_module_label) AS elem
            UNION ALL
            SELECT jsonb_build_object('label', 'Tittel', 'value', coalesce(p_title, '—'))
            UNION ALL
            SELECT jsonb_build_object('label', 'Antall', 'value', v_count::text)
            WHERE v_count > 1
            UNION ALL
            SELECT jsonb_build_object('label', 'Oppfølgingsfrist', 'value', v_due)
            WHERE v_due IS NOT NULL
            UNION ALL
            SELECT jsonb_build_object('label', 'Oppsummering', 'value', left(trim(p_summary), 500))
            WHERE nullif(trim(p_summary), '') IS NOT NULL
          ) parts
        ),
        'Åpne DriftPro',
        'https://driftpro.no',
        v_subject
      );
    EXCEPTION WHEN undefined_function THEN
      v_html := v_body;
    END;

    IF coalesce(p_send_email, true) AND coalesce(v_email, '') <> '' THEN
      PERFORM public.queue_email_if_allowed(
        p_company_id,
        v_rec,
        v_email,
        v_subject,
        coalesce(v_html, v_body),
        'hms_follow_up',
        'hms_follow_ups',
        v_id,
        'hms',
        'HMS oppfølging',
        false
      );
    END IF;

    IF coalesce(p_send_push, true) THEN
      PERFORM public.hms_push_notification(
        v_rec,
        p_company_id,
        v_subject,
        left(v_push_body, 200),
        jsonb_build_object(
          'category', 'hms_follow_up',
          'reference_type', 'hms_follow_ups',
          'reference_id', v_id::text,
          'module', p_module,
          'source_type', p_reference_type,
          'source_id', p_reference_id::text
        ),
        'hms'
      );
    END IF;
  END LOOP;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.hms_create_follow_up_notify(
  UUID, TEXT, TEXT, UUID, TEXT, TEXT, INT, DATE, UUID[], BOOLEAN, BOOLEAN
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.hms_close_follow_up(
  p_follow_up_id UUID,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.hms_follow_ups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.hms_follow_ups;
BEGIN
  SELECT * INTO v_row FROM public.hms_follow_ups WHERE id = p_follow_up_id;
  IF v_row IS NULL THEN
    RAISE EXCEPTION 'Fant ikke oppfølging';
  END IF;

  IF v_row.company_id IS DISTINCT FROM public.get_user_company_id()
     AND NOT public.is_company_admin() THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  IF NOT (
    public.is_company_admin()
    OR v_row.created_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.hms_follow_up_recipients r
      WHERE r.follow_up_id = p_follow_up_id AND r.profile_id = auth.uid()
    )
  ) THEN
    RAISE EXCEPTION 'Kun involverte kan lukke oppfølgingen';
  END IF;

  IF v_row.status = 'closed' THEN
    RETURN v_row;
  END IF;

  UPDATE public.hms_follow_ups
  SET status = 'closed',
      closed_at = now(),
      closed_by = auth.uid(),
      close_notes = nullif(trim(p_notes), ''),
      updated_at = now()
  WHERE id = p_follow_up_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.hms_close_follow_up(UUID, TEXT)
  TO authenticated, service_role;

-- Når avvik lukkes: lukk tilhørende åpne oppfølginger (stopper purring).
CREATE OR REPLACE FUNCTION public.hms_follow_up_on_ticket_closed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'lukket'::public.ticket_status
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
    UPDATE public.hms_follow_ups
    SET status = 'closed',
        closed_at = coalesce(closed_at, now()),
        closed_by = coalesce(closed_by, NEW.resolved_by, auth.uid()),
        close_notes = coalesce(close_notes, 'Lukket automatisk da avviket ble lukket'),
        updated_at = now()
    WHERE reference_type = 'tickets'
      AND reference_id = NEW.id
      AND status = 'open';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_hms_follow_up_ticket_closed ON public.tickets;
CREATE TRIGGER trg_hms_follow_up_ticket_closed
  AFTER INSERT OR UPDATE OF status ON public.tickets
  FOR EACH ROW
  EXECUTE FUNCTION public.hms_follow_up_on_ticket_closed();

-- Påminnelse dagen før frist hvis fortsatt åpen.
CREATE OR REPLACE FUNCTION public.notify_hms_follow_up_reminders()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  rcp RECORD;
  n INT := 0;
  v_due TEXT;
  v_module_label TEXT;
  v_subject TEXT;
  v_body TEXT;
  v_html TEXT;
  v_push TEXT;
BEGIN
  FOR rec IN
    SELECT f.*
    FROM public.hms_follow_ups f
    WHERE f.status = 'open'
      AND f.follow_up_due_at IS NOT NULL
      AND f.follow_up_due_at = (CURRENT_DATE + 1)
      AND (f.last_reminder_on IS NULL OR f.last_reminder_on < CURRENT_DATE)
  LOOP
    v_due := public.format_nb_date(rec.follow_up_due_at);
    v_module_label := public.hms_module_label(rec.module);

    FOR rcp IN
      SELECT p.id, p.full_name, p.email
      FROM public.hms_follow_up_recipients fr
      JOIN public.profiles p ON p.id = fr.profile_id
      WHERE fr.follow_up_id = rec.id
    LOOP
      v_subject := format(
        'Påminnelse: følg opp %s i morgen (frist %s)',
        v_module_label,
        coalesce(v_due, '')
      );
      v_push := format(
        'Frist i morgen (%s) for %s «%s». Lukkes ikke før oppfølging er ferdig.',
        coalesce(v_due, '—'),
        v_module_label,
        left(rec.title, 40)
      );
      v_body := format(
        E'Hei %s,\n\n'
        || 'Dette er en påminnelse: oppfølgingsfrist for %s er i morgen (%s).\n\n'
        || 'Tittel: %s\n'
        || CASE WHEN rec.deviation_count > 1
             THEN format('Antall punkter/avvik: %s\n', rec.deviation_count)
             ELSE '' END
        || CASE WHEN nullif(trim(rec.summary), '') IS NOT NULL
             THEN format(E'\nOppsummering:\n%s\n', trim(rec.summary))
             ELSE '' END
        || E'\nLukk oppfølgingen i DriftPro når tiltak er utført — da sendes ingen flere purringer.\n'
        || 'https://driftpro.no\n',
        coalesce(rcp.full_name, 'Kollega'),
        v_module_label,
        coalesce(v_due, '—'),
        rec.title
      );

      BEGIN
        v_html := public.build_driftpro_email_html(
          format('Påminnelse · %s', v_module_label),
          format('Oppfølgingsfrist er i morgen (%s). Saken er fortsatt åpen.', coalesce(v_due, '—')),
          jsonb_build_array(
            jsonb_build_object('label', 'Modul', 'value', v_module_label),
            jsonb_build_object('label', 'Tittel', 'value', rec.title),
            jsonb_build_object('label', 'Frist', 'value', coalesce(v_due, '—'))
          ),
          'Åpne DriftPro',
          'https://driftpro.no',
          v_subject
        );
      EXCEPTION WHEN undefined_function THEN
        v_html := v_body;
      END;

      IF coalesce(rec.send_email, true) AND coalesce(rcp.email, '') <> '' THEN
        IF public.queue_email_if_allowed(
          rec.company_id,
          rcp.id,
          rcp.email,
          v_subject,
          coalesce(v_html, v_body),
          'hms_follow_up_reminder',
          'hms_follow_ups',
          rec.id,
          'hms',
          'HMS oppfølgingspåminnelse',
          false
        ) IS NOT NULL THEN
          n := n + 1;
        END IF;
      END IF;

      IF coalesce(rec.send_push, true) THEN
        PERFORM public.hms_push_notification(
          rcp.id,
          rec.company_id,
          v_subject,
          left(v_push, 200),
          jsonb_build_object(
            'category', 'hms_follow_up_reminder',
            'reference_type', 'hms_follow_ups',
            'reference_id', rec.id::text,
            'module', rec.module
          ),
          'hms'
        );
      END IF;
    END LOOP;

    UPDATE public.hms_follow_ups
    SET last_reminder_on = CURRENT_DATE,
        updated_at = now()
    WHERE id = rec.id;
  END LOOP;

  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_hms_follow_up_reminders()
  TO service_role;

DO $cronsetup$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      PERFORM cron.unschedule('driftpro-hms-followup-reminders');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    PERFORM cron.schedule(
      'driftpro-hms-followup-reminders',
      '30 5 * * *',
      $cron$SELECT public.notify_hms_follow_up_reminders();$cron$
    );
  END IF;
END;
$cronsetup$;
