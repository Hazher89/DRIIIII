-- Bilkontroll-avvik: SMS til bedriftsansvarlig + e-post til kontrollør/oppfølger.
-- SMS: kontroll utført, avvik meldt, logg inn i DriftPro-portalen.
-- E-post: påminnelse om oppfølgingskontroll med dato og forrige avvik.

CREATE OR REPLACE FUNCTION public.format_nb_date(p_date DATE)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_date IS NULL THEN NULL
    ELSE to_char(p_date, 'DD.MM.YYYY')
  END;
$$;

CREATE OR REPLACE FUNCTION public.partner_vehicle_inspection_vehicle_label(
  p_registration_number TEXT,
  p_unit_code TEXT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN nullif(trim(coalesce(p_registration_number, '')), '') IS NOT NULL
      AND trim(p_registration_number) <> '—'
      THEN upper(replace(trim(p_registration_number), ' ', ''))
    WHEN nullif(trim(coalesce(p_unit_code, '')), '') IS NOT NULL
      THEN upper(trim(p_unit_code))
    ELSE 'kjøretøy'
  END;
$$;

-- Varsel ved nytt avvik (kalles etter lagring av bilkontroll).
CREATE OR REPLACE FUNCTION public.notify_partner_vehicle_inspection_deviation(
  p_inspection_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  ins RECORD;
  v_partner_name TEXT;
  v_vehicle TEXT;
  v_sms TEXT;
  v_owner_subject TEXT;
  v_owner_body TEXT;
  v_owner_html TEXT;
  v_inspector_subject TEXT;
  v_inspector_body TEXT;
  v_inspector_html TEXT;
  v_follow_date TEXT;
  v_next_date TEXT;
  v_notes TEXT;
  v_inspector_email TEXT;
  v_assignee_email TEXT;
  v_assignee_id UUID;
  sms_n INT := 0;
  email_n INT := 0;
  inspector_n INT := 0;
BEGIN
  SELECT
    i.*,
    p.name AS partner_name,
    p.trade_name AS partner_trade_name,
    p.is_active AS partner_active,
    insp.email AS inspector_email,
    insp.full_name AS inspector_name,
    asn.email AS assignee_email,
    asn.full_name AS assignee_name
  INTO ins
  FROM public.partner_vehicle_inspections i
  JOIN public.partners p ON p.id = i.partner_id
  LEFT JOIN public.profiles insp ON insp.id = i.inspected_by
  LEFT JOIN public.profiles asn ON asn.id = i.deviation_assignee
  WHERE i.id = p_inspection_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  IF NOT coalesce(ins.has_deviation, false) THEN
    RETURN jsonb_build_object('ok', true, 'skipped', true, 'reason', 'no_deviation');
  END IF;

  IF NOT coalesce(ins.partner_active, false) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'partner_inactive');
  END IF;

  v_partner_name := coalesce(nullif(trim(ins.partner_trade_name), ''), ins.partner_name, 'Samarbeidspartner');
  v_vehicle := public.partner_vehicle_inspection_vehicle_label(ins.registration_number, ins.unit_code);
  v_follow_date := public.format_nb_date(ins.follow_up_due_at);
  v_next_date := public.format_nb_date(ins.next_inspection_at);
  v_notes := nullif(trim(coalesce(ins.deviation_notes, '')), '');
  IF v_notes IS NULL THEN
    v_notes := 'Se detaljer i DriftPro-portalen.';
  END IF;

  -- SMS til bedriftsansvarlig / bileier (kort og profesjonell).
  v_sms := format(
    'MAVI Logistikk: Bilkontroll er utført på %s (%s). Det er registrert avvik. '
    || 'Logg inn i DriftPro-portalen for å se avvik%s. '
    || 'https://driftpro.no',
    v_vehicle,
    v_partner_name,
    CASE
      WHEN v_next_date IS NOT NULL THEN ' og planlagt neste kontroll ' || v_next_date
      WHEN v_follow_date IS NOT NULL THEN ' og oppfølgingsfrist ' || v_follow_date
      ELSE ''
    END
  );

  sms_n := public.notify_partner_owner_phones(
    ins.company_id,
    ins.partner_id,
    v_sms,
    'partner_vehicle_inspection',
    'partner_meeting',
    'partner_vehicle_inspections',
    ins.id,
    'Bilkontroll avvik → bedriftsansvarlig (SMS)'
  );

  v_owner_subject := format('Bilkontroll — avvik registrert (%s)', v_vehicle);
  v_owner_body := format(
    E'Hei,\n\n'
    || 'MAVI Logistikk har gjennomført bilkontroll på %s for %s.\n\n'
    || 'Det er registrert avvik som krever oppfølging.\n\n'
    || 'Avvik: %s\n'
    || '%s'
    || '%s'
    || E'\nLogg inn i DriftPro-portalen for å se detaljer, dokumentasjon og neste kontroll:\n'
    || 'https://driftpro.no\n\n'
    || 'Med vennlig hilsen\nMAVI Logistikk AS\nDriftPro',
    v_vehicle,
    v_partner_name,
    v_notes,
    CASE WHEN v_follow_date IS NOT NULL THEN 'Oppfølgingsfrist: ' || v_follow_date || E'\n' ELSE '' END,
    CASE WHEN v_next_date IS NOT NULL THEN 'Neste planlagte kontroll: ' || v_next_date || E'\n' ELSE '' END
  );

  BEGIN
    v_owner_html := public.build_driftpro_email_html(
      'Avvik etter bilkontroll',
      format(
        'MAVI Logistikk har gjennomført bilkontroll på %s. Det er registrert avvik som krever oppfølging. Logg inn i DriftPro for å se detaljer.',
        v_vehicle
      ),
      jsonb_build_array(
        jsonb_build_object('label', 'Bedrift', 'value', v_partner_name),
        jsonb_build_object('label', 'Kjøretøy', 'value', v_vehicle),
        jsonb_build_object('label', 'Avvik', 'value', v_notes),
        jsonb_build_object('label', 'Oppfølgingsfrist', 'value', coalesce(v_follow_date, '—')),
        jsonb_build_object('label', 'Neste kontroll', 'value', coalesce(v_next_date, '—'))
      ),
      'Åpne DriftPro-portalen',
      'https://driftpro.no',
      format('Avvik registrert på %s', v_vehicle)
    );
  EXCEPTION WHEN undefined_function THEN
    v_owner_html := v_owner_body;
  END;

  email_n := public.notify_partner_owner_emails(
    ins.company_id,
    ins.partner_id,
    v_owner_subject,
    coalesce(v_owner_html, v_owner_body),
    'partner_vehicle_inspection',
    'partner_meeting',
    'partner_vehicle_inspections',
    ins.id,
    'Bilkontroll avvik → bedriftsansvarlig (e-post)'
  );

  -- E-post til kontrollør / saksbehandler: må følge opp med dato + forrige avvik.
  v_assignee_id := coalesce(ins.deviation_assignee, ins.inspected_by);
  v_inspector_email := nullif(trim(lower(coalesce(ins.inspector_email, ''))), '');
  v_assignee_email := nullif(trim(lower(coalesce(ins.assignee_email, ''))), '');

  v_inspector_subject := format(
    'Oppfølging bilkontroll — %s · frist %s',
    v_vehicle,
    coalesce(v_follow_date, 'ikke satt')
  );
  v_inspector_body := format(
    E'Hei,\n\n'
    || 'Du har ansvar for oppfølging etter bilkontroll.\n\n'
    || 'Bedrift: %s\n'
    || 'Kjøretøy: %s\n'
    || 'Kontrolldato: %s\n'
    || 'Oppfølgingsfrist: %s\n'
    || 'Avvik fra forrige kontroll:\n%s\n\n'
    || 'Logg inn i DriftPro og gå til Bilkontroll for å følge opp og lukke avviket.\n'
    || 'https://driftpro.no\n\n'
    || 'Med vennlig hilsen\nDriftPro',
    v_partner_name,
    v_vehicle,
    to_char(ins.inspected_at AT TIME ZONE 'Europe/Oslo', 'DD.MM.YYYY HH24:MI'),
    coalesce(v_follow_date, 'ikke satt'),
    v_notes
  );

  BEGIN
    v_inspector_html := public.build_driftpro_email_html(
      'Oppfølging etter bilkontroll',
      'Du må følge opp kjøretøyet. Se frist og avvik fra forrige kontroll nedenfor.',
      jsonb_build_array(
        jsonb_build_object('label', 'Bedrift', 'value', v_partner_name),
        jsonb_build_object('label', 'Kjøretøy', 'value', v_vehicle),
        jsonb_build_object('label', 'Kontrolldato', 'value', to_char(ins.inspected_at AT TIME ZONE 'Europe/Oslo', 'DD.MM.YYYY HH24:MI')),
        jsonb_build_object('label', 'Oppfølgingsfrist', 'value', coalesce(v_follow_date, 'ikke satt')),
        jsonb_build_object('label', 'Avvik forrige kontroll', 'value', v_notes)
      ),
      'Åpne Bilkontroll',
      'https://driftpro.no',
      format('Oppfølging %s — frist %s', v_vehicle, coalesce(v_follow_date, 'snart'))
    );
  EXCEPTION WHEN undefined_function THEN
    v_inspector_html := v_inspector_body;
  END;

  -- Send til assignee (ofte samme som inspector), deretter inspector hvis annen e-post.
  IF v_assignee_id IS NOT NULL THEN
    IF public.queue_email_if_allowed(
      ins.company_id,
      v_assignee_id,
      coalesce(v_assignee_email, v_inspector_email),
      v_inspector_subject,
      coalesce(v_inspector_html, v_inspector_body),
      'partner_vehicle_inspection_followup',
      'partner_vehicle_inspections',
      ins.id,
      'general',
      'Bilkontroll oppfølging → kontrollør',
      false
    ) IS NOT NULL THEN
      inspector_n := inspector_n + 1;
    END IF;
  END IF;

  IF ins.inspected_by IS NOT NULL
     AND (v_assignee_id IS NULL OR ins.inspected_by IS DISTINCT FROM v_assignee_id)
     AND v_inspector_email IS NOT NULL THEN
    IF public.queue_email_if_allowed(
      ins.company_id,
      ins.inspected_by,
      v_inspector_email,
      v_inspector_subject,
      coalesce(v_inspector_html, v_inspector_body),
      'partner_vehicle_inspection_followup',
      'partner_vehicle_inspections',
      ins.id,
      'general',
      'Bilkontroll oppfølging → kontrollør (inspektør)',
      false
    ) IS NOT NULL THEN
      inspector_n := inspector_n + 1;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'sms_to_owners', sms_n,
    'email_to_owners', email_n,
    'email_to_inspectors', inspector_n,
    'vehicle', v_vehicle,
    'partner', v_partner_name
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_partner_vehicle_inspection_deviation(UUID)
  TO authenticated, service_role;

-- Daglig purring: åpne avvik med frist i dag / i morgen → e-post til kontrollør.
CREATE OR REPLACE FUNCTION public.notify_partner_vehicle_inspection_followup_reminders()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  n INT := 0;
  v_vehicle TEXT;
  v_partner_name TEXT;
  v_follow_date TEXT;
  v_notes TEXT;
  v_subject TEXT;
  v_body TEXT;
  v_html TEXT;
  v_email TEXT;
  v_uid UUID;
BEGIN
  FOR rec IN
    SELECT
      i.*,
      p.name AS partner_name,
      p.trade_name AS partner_trade_name,
      coalesce(asn.email, insp.email) AS to_email,
      coalesce(i.deviation_assignee, i.inspected_by) AS to_user_id
    FROM public.partner_vehicle_inspections i
    JOIN public.partners p ON p.id = i.partner_id AND p.is_active = true
    LEFT JOIN public.profiles insp ON insp.id = i.inspected_by
    LEFT JOIN public.profiles asn ON asn.id = i.deviation_assignee
    WHERE i.has_deviation = true
      AND i.follow_up_acknowledged_at IS NULL
      AND i.follow_up_due_at IS NOT NULL
      AND i.follow_up_due_at <= (CURRENT_DATE + 1)
      AND i.follow_up_due_at >= (CURRENT_DATE - 3)
  LOOP
    v_uid := rec.to_user_id;
    v_email := nullif(trim(lower(coalesce(rec.to_email, ''))), '');
    IF v_uid IS NULL OR v_email IS NULL THEN
      CONTINUE;
    END IF;

    -- Unngå dobbel purring samme dag (audit).
    IF EXISTS (
      SELECT 1
      FROM public.notification_audit a
      WHERE a.reference_type = 'partner_vehicle_inspections'
        AND a.reference_id = rec.id
        AND a.setting_key = 'general'
        AND a.category = 'partner_vehicle_inspection_reminder'
        AND a.status = 'queued'
        AND a.created_at::date = CURRENT_DATE
    ) THEN
      CONTINUE;
    END IF;

    v_partner_name := coalesce(nullif(trim(rec.partner_trade_name), ''), rec.partner_name, 'Samarbeidspartner');
    v_vehicle := public.partner_vehicle_inspection_vehicle_label(rec.registration_number, rec.unit_code);
    v_follow_date := public.format_nb_date(rec.follow_up_due_at);
    v_notes := coalesce(nullif(trim(rec.deviation_notes), ''), 'Se bilkontroll i DriftPro.');

    v_subject := format('Påminnelse: bilkontroll oppfølging %s (frist %s)', v_vehicle, coalesce(v_follow_date, ''));
    v_body := format(
      E'Hei,\n\n'
      || 'Påminnelse: bilen %s hos %s må kontrolleres / følges opp.\n\n'
      || 'Frist: %s\n'
      || 'Avvik i forrige kontroll:\n%s\n\n'
      || 'Åpne DriftPro → Bilkontroll.\nhttps://driftpro.no\n',
      v_vehicle, v_partner_name, coalesce(v_follow_date, '—'), v_notes
    );

    BEGIN
      v_html := public.build_driftpro_email_html(
        'Påminnelse: bilkontroll',
        format('Bilen %s må følges opp. Se frist og avvik fra forrige kontroll.', v_vehicle),
        jsonb_build_array(
          jsonb_build_object('label', 'Bedrift', 'value', v_partner_name),
          jsonb_build_object('label', 'Kjøretøy', 'value', v_vehicle),
          jsonb_build_object('label', 'Oppfølgingsfrist', 'value', coalesce(v_follow_date, '—')),
          jsonb_build_object('label', 'Avvik forrige kontroll', 'value', v_notes)
        ),
        'Åpne Bilkontroll',
        'https://driftpro.no',
        v_subject
      );
    EXCEPTION WHEN undefined_function THEN
      v_html := v_body;
    END;

    IF public.queue_email_if_allowed(
      rec.company_id,
      v_uid,
      v_email,
      v_subject,
      coalesce(v_html, v_body),
      'partner_vehicle_inspection_reminder',
      'partner_vehicle_inspections',
      rec.id,
      'general',
      'Bilkontroll oppfølgingspurring',
      false
    ) IS NOT NULL THEN
      n := n + 1;
    END IF;
  END LOOP;

  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_partner_vehicle_inspection_followup_reminders()
  TO service_role;

-- Cron: daglig ca. 07:30 norsk tid (05:30 UTC).
DO $cronsetup$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      PERFORM cron.unschedule('driftpro-bilkontroll-followup-reminders');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    PERFORM cron.schedule(
      'driftpro-bilkontroll-followup-reminders',
      '30 5 * * *',
      $job$SELECT public.notify_partner_vehicle_inspection_followup_reminders()$job$
    );
  ELSE
    RAISE NOTICE 'pg_cron ikke tilgjengelig — kjør notify_partner_vehicle_inspection_followup_reminders manuelt / via Dashboard Cron';
  END IF;
END;
$cronsetup$;

