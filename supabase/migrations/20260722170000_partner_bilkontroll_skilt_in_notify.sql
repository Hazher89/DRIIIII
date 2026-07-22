-- Bedre kjøretøy-tekst med skiltnummer i SMS/push ved bilkontroll.

CREATE OR REPLACE FUNCTION public.partner_vehicle_inspection_vehicle_label(
  p_registration_number TEXT,
  p_unit_code TEXT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN nullif(trim(replace(coalesce(p_registration_number, ''), '—', '')), '') IS NOT NULL
      THEN upper(replace(trim(replace(p_registration_number, '—', '')), ' ', ''))
    WHEN upper(trim(coalesce(p_unit_code, ''))) LIKE 'REG-%'
      THEN upper(replace(trim(substring(p_unit_code from 5)), ' ', ''))
    WHEN nullif(trim(coalesce(p_unit_code, '')), '') IS NOT NULL
      THEN upper(trim(p_unit_code))
    ELSE 'kjøretøy'
  END;
$$;

-- Henter skilt + MAVI for en inspeksjon (fra rad eller partner_vehicles).
CREATE OR REPLACE FUNCTION public.partner_vehicle_inspection_display(
  p_inspection_id UUID,
  OUT o_plate TEXT,
  OUT o_mavi TEXT,
  OUT o_label TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  ins RECORD;
  v_plate TEXT;
  v_mavi TEXT;
  v_unit TEXT;
BEGIN
  SELECT
    i.registration_number,
    i.unit_code,
    pv.registration_number AS vehicle_reg,
    pv.unit_code AS vehicle_unit
  INTO ins
  FROM public.partner_vehicle_inspections i
  LEFT JOIN public.partner_vehicles pv ON pv.id = i.partner_vehicle_id
  WHERE i.id = p_inspection_id;

  IF NOT FOUND THEN
    o_plate := NULL;
    o_mavi := NULL;
    o_label := 'kjøretøy';
    RETURN;
  END IF;

  v_plate := nullif(trim(replace(coalesce(ins.registration_number, ''), '—', '')), '');
  IF v_plate IS NULL THEN
    v_plate := nullif(trim(replace(coalesce(ins.vehicle_reg, ''), '—', '')), '');
  END IF;
  IF v_plate IS NULL AND upper(trim(coalesce(ins.unit_code, ''))) LIKE 'REG-%' THEN
    v_plate := nullif(trim(substring(ins.unit_code from 5)), '');
  END IF;
  IF v_plate IS NULL AND upper(trim(coalesce(ins.vehicle_unit, ''))) LIKE 'REG-%' THEN
    v_plate := nullif(trim(substring(ins.vehicle_unit from 5)), '');
  END IF;
  IF v_plate IS NOT NULL THEN
    v_plate := upper(replace(v_plate, ' ', ''));
  END IF;

  v_unit := coalesce(nullif(trim(ins.unit_code), ''), nullif(trim(ins.vehicle_unit), ''));
  IF v_unit IS NOT NULL
     AND upper(v_unit) NOT LIKE 'REG-%'
     AND upper(v_unit) LIKE 'NO_O_M%' THEN
    v_mavi := upper(v_unit);
  ELSIF v_unit IS NOT NULL AND upper(v_unit) NOT LIKE 'REG-%' THEN
    v_mavi := upper(v_unit);
  ELSE
    v_mavi := NULL;
  END IF;

  o_plate := v_plate;
  o_mavi := v_mavi;
  IF v_plate IS NOT NULL AND v_mavi IS NOT NULL THEN
    o_label := 'skiltnummer ' || v_plate || ' (' || v_mavi || ')';
  ELSIF v_plate IS NOT NULL THEN
    o_label := 'skiltnummer ' || v_plate;
  ELSIF v_mavi IS NOT NULL THEN
    o_label := v_mavi;
  ELSE
    o_label := 'kjøretøy';
  END IF;
END;
$$;

-- Oppdater notify til å bruke display med skiltnummer, og beholde kanalvalg.
CREATE OR REPLACE FUNCTION public.notify_partner_vehicle_inspection_completed(
  p_inspection_id UUID,
  p_send_sms BOOLEAN DEFAULT true,
  p_send_push BOOLEAN DEFAULT true,
  p_send_email BOOLEAN DEFAULT true
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
  v_plate TEXT;
  v_mavi TEXT;
  v_sms TEXT;
  v_push_title TEXT;
  v_push_body TEXT;
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
  v_has_dev BOOLEAN;
  sms_n INT := 0;
  email_n INT := 0;
  push_n INT := 0;
  inspector_n INT := 0;
  disp RECORD;
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

  IF NOT coalesce(ins.partner_active, false) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'partner_inactive');
  END IF;

  IF NOT coalesce(p_send_sms, false)
     AND NOT coalesce(p_send_push, false)
     AND NOT coalesce(p_send_email, false) THEN
    RETURN jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'no_channels',
      'sms_to_owners', 0,
      'push_to_owners', 0,
      'email_to_owners', 0
    );
  END IF;

  SELECT * INTO disp FROM public.partner_vehicle_inspection_display(p_inspection_id);
  v_vehicle := coalesce(disp.o_label, 'kjøretøy');
  v_plate := disp.o_plate;
  v_mavi := disp.o_mavi;

  v_has_dev := coalesce(ins.has_deviation, false);
  v_partner_name := coalesce(nullif(trim(ins.partner_trade_name), ''), ins.partner_name, 'Samarbeidspartner');
  v_follow_date := public.format_nb_date(ins.follow_up_due_at);
  v_next_date := public.format_nb_date(ins.next_inspection_at);
  v_notes := nullif(trim(coalesce(ins.deviation_notes, '')), '');
  IF v_notes IS NULL AND v_has_dev THEN
    v_notes := 'Se detaljer i DriftPro-portalen.';
  END IF;

  IF v_has_dev THEN
    v_sms := format(
      'MAVI Logistikk: Bilkontroll er utført på bil med %s hos %s. Det er registrert AVVIK. '
      || 'Logg inn i DriftPro for å se avvik%s: https://driftpro.no',
      v_vehicle,
      v_partner_name,
      CASE
        WHEN v_next_date IS NOT NULL THEN ' og neste kontroll ' || v_next_date
        WHEN v_follow_date IS NOT NULL THEN ' og oppfølgingsfrist ' || v_follow_date
        ELSE ''
      END
    );
    v_push_title := CASE
      WHEN v_plate IS NOT NULL THEN 'Avvik — skilt ' || v_plate
      ELSE 'Avvik etter bilkontroll'
    END;
    v_push_body := format(
      'Bil med %s hos %s — avvik registrert. Åpne DriftPro for detaljer.',
      v_vehicle, v_partner_name
    );
    v_owner_subject := format(
      'Bilkontroll — avvik (%s)',
      coalesce(v_plate, v_mavi, 'kjøretøy')
    );
  ELSE
    v_sms := format(
      'MAVI Logistikk: Bilkontroll er utført på bil med %s hos %s. '
      || 'Logg inn i DriftPro-portalen for rapport%s: https://driftpro.no',
      v_vehicle,
      v_partner_name,
      CASE WHEN v_next_date IS NOT NULL THEN ' og neste kontroll ' || v_next_date ELSE '' END
    );
    v_push_title := CASE
      WHEN v_plate IS NOT NULL THEN 'Bilkontroll — skilt ' || v_plate
      ELSE 'Bilkontroll utført'
    END;
    v_push_body := format(
      'Bil med %s hos %s — kontroll arkivert. Åpne DriftPro for rapport.',
      v_vehicle, v_partner_name
    );
    v_owner_subject := format(
      'Bilkontroll utført (%s)',
      coalesce(v_plate, v_mavi, 'kjøretøy')
    );
  END IF;

  IF coalesce(p_send_sms, false) THEN
    sms_n := public.notify_partner_owner_phones(
      ins.company_id,
      ins.partner_id,
      v_sms,
      'partner_vehicle_inspection',
      'partner_meeting',
      'partner_vehicle_inspections',
      ins.id,
      CASE WHEN v_has_dev
        THEN 'Bilkontroll avvik → bedriftsansvarlig (SMS)'
        ELSE 'Bilkontroll OK → bedriftsansvarlig (SMS)'
      END
    );
  END IF;

  IF coalesce(p_send_push, false) THEN
    push_n := public.notify_partner_vehicle_inspection_owner_push(
      ins.company_id,
      ins.partner_id,
      ins.id,
      v_push_title,
      v_push_body
    );
  END IF;

  IF coalesce(p_send_email, false) THEN
    v_owner_body := format(
      E'Hei,\n\n'
      || 'MAVI Logistikk har gjennomført bilkontroll på bil med %s for %s.\n\n'
      || '%s'
      || '%s'
      || '%s'
      || E'\nLogg inn i DriftPro-portalen:\nhttps://driftpro.no\n\n'
      || 'Med vennlig hilsen\nMAVI Logistikk AS\nDriftPro',
      v_vehicle,
      v_partner_name,
      CASE
        WHEN v_has_dev THEN 'Det er registrert avvik som krever oppfølging.' || E'\n\nAvvik: ' || coalesce(v_notes, '') || E'\n'
        ELSE 'Kontrollen er gjennomført uten avvik.' || E'\n'
      END,
      CASE WHEN v_follow_date IS NOT NULL THEN 'Oppfølgingsfrist: ' || v_follow_date || E'\n' ELSE '' END,
      CASE WHEN v_next_date IS NOT NULL THEN 'Neste planlagte kontroll: ' || v_next_date || E'\n' ELSE '' END
    );

    BEGIN
      v_owner_html := public.build_driftpro_email_html(
        CASE WHEN v_has_dev THEN 'Avvik etter bilkontroll' ELSE 'Bilkontroll utført' END,
        CASE
          WHEN v_has_dev THEN format(
            'Bilkontroll er utført på bil med %s. Det er registrert avvik. Logg inn i DriftPro for detaljer.',
            v_vehicle
          )
          ELSE format(
            'Bilkontroll er utført på bil med %s. Rapporten er tilgjengelig i DriftPro.',
            v_vehicle
          )
        END,
        jsonb_build_array(
          jsonb_build_object('label', 'Bedrift', 'value', v_partner_name),
          jsonb_build_object('label', 'Skiltnummer', 'value', coalesce(v_plate, '—')),
          jsonb_build_object('label', 'MAVI', 'value', coalesce(v_mavi, '—')),
          jsonb_build_object('label', 'Status', 'value', CASE WHEN v_has_dev THEN 'Avvik' ELSE 'OK' END),
          jsonb_build_object('label', 'Avvik', 'value', coalesce(v_notes, '—')),
          jsonb_build_object('label', 'Oppfølgingsfrist', 'value', coalesce(v_follow_date, '—')),
          jsonb_build_object('label', 'Neste kontroll', 'value', coalesce(v_next_date, '—'))
        ),
        'Åpne DriftPro-portalen',
        'https://driftpro.no',
        v_owner_subject
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
      CASE WHEN v_has_dev
        THEN 'Bilkontroll avvik → bedriftsansvarlig (e-post)'
        ELSE 'Bilkontroll OK → bedriftsansvarlig (e-post)'
      END
    );
  END IF;

  IF v_has_dev THEN
    v_assignee_id := coalesce(ins.deviation_assignee, ins.inspected_by);
    v_inspector_email := nullif(trim(lower(coalesce(ins.inspector_email, ''))), '');
    v_assignee_email := nullif(trim(lower(coalesce(ins.assignee_email, ''))), '');

    v_inspector_subject := format(
      'Oppfølging bilkontroll — %s · frist %s',
      coalesce(v_plate, v_mavi, 'kjøretøy'),
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
      || 'Logg inn i DriftPro → Bilkontroll.\nhttps://driftpro.no\n',
      v_partner_name,
      v_vehicle,
      to_char(ins.inspected_at AT TIME ZONE 'Europe/Oslo', 'DD.MM.YYYY HH24:MI'),
      coalesce(v_follow_date, 'ikke satt'),
      coalesce(v_notes, '—')
    );

    BEGIN
      v_inspector_html := public.build_driftpro_email_html(
        'Oppfølging etter bilkontroll',
        'Du må følge opp kjøretøyet. Se frist og avvik fra forrige kontroll nedenfor.',
        jsonb_build_array(
          jsonb_build_object('label', 'Bedrift', 'value', v_partner_name),
          jsonb_build_object('label', 'Skiltnummer', 'value', coalesce(v_plate, '—')),
          jsonb_build_object('label', 'MAVI', 'value', coalesce(v_mavi, '—')),
          jsonb_build_object('label', 'Kontrolldato', 'value', to_char(ins.inspected_at AT TIME ZONE 'Europe/Oslo', 'DD.MM.YYYY HH24:MI')),
          jsonb_build_object('label', 'Oppfølgingsfrist', 'value', coalesce(v_follow_date, 'ikke satt')),
          jsonb_build_object('label', 'Avvik forrige kontroll', 'value', coalesce(v_notes, '—'))
        ),
        'Åpne Bilkontroll',
        'https://driftpro.no',
        v_inspector_subject
      );
    EXCEPTION WHEN undefined_function THEN
      v_inspector_html := v_inspector_body;
    END;

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
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'has_deviation', v_has_dev,
    'sms_to_owners', sms_n,
    'push_to_owners', push_n,
    'email_to_owners', email_n,
    'email_to_inspectors', inspector_n,
    'vehicle', v_vehicle,
    'plate', v_plate,
    'partner', v_partner_name
  );
END;
$$;

DROP FUNCTION IF EXISTS public.notify_partner_vehicle_inspection_completed(UUID);

GRANT EXECUTE ON FUNCTION public.partner_vehicle_inspection_display(UUID)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.notify_partner_vehicle_inspection_completed(UUID, BOOLEAN, BOOLEAN, BOOLEAN)
  TO authenticated, service_role;
