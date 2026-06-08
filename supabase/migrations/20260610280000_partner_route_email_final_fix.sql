-- ÉN e-post per rute, profesjonell HTML, ingen «avvis», gammel trigger av.
-- Kjør også: supabase functions deploy send-email-outbox (HTML-støtte).

CREATE OR REPLACE FUNCTION public.escape_html(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT replace(
    replace(
      replace(
        replace(coalesce(p_text, ''), '&', '&amp;'),
        '<', '&lt;'
      ),
      '>', '&gt;'
    ),
    '"', '&quot;'
  );
$$;

CREATE OR REPLACE FUNCTION public.build_driftpro_email_html(
  p_heading text,
  p_intro text,
  p_detail_rows jsonb DEFAULT '[]'::jsonb,
  p_cta_label text DEFAULT 'Åpne DriftPro',
  p_cta_url text DEFAULT 'https://driftpro.no',
  p_preheader text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_rows text := '';
  v_row jsonb;
  v_label text;
  v_value text;
BEGIN
  FOR v_row IN SELECT value FROM jsonb_array_elements(coalesce(p_detail_rows, '[]'::jsonb))
  LOOP
    v_label := public.escape_html(v_row->>'label');
    v_value := public.escape_html(v_row->>'value');
    IF coalesce(v_value, '') <> '' THEN
      v_rows := v_rows || format(
        '<tr><td style="padding:10px 0;color:#64748b;font-size:13px;width:38%%;vertical-align:top;border-bottom:1px solid #eef2f0;">%s</td>'
        || '<td style="padding:10px 0;color:#0f172a;font-size:14px;font-weight:600;border-bottom:1px solid #eef2f0;">%s</td></tr>',
        v_label, v_value
      );
    END IF;
  END LOOP;

  RETURN format($html$
<!DOCTYPE html>
<html lang="nb">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%s</title>
</head>
<body style="margin:0;padding:0;background:#eef2f0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
%s
<table role="presentation" width="100%%" cellspacing="0" cellpadding="0" style="background:#eef2f0;padding:32px 16px;">
<tr><td align="center">
<table role="presentation" width="100%%" style="max-width:580px;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 12px 40px rgba(15,23,42,0.10);">
<tr><td style="background:linear-gradient(135deg,#0D3B13 0%%,#1B5E20 45%%,#2E7D32 100%%);padding:32px 32px 28px;">
<div style="font-size:12px;font-weight:700;letter-spacing:0.12em;text-transform:uppercase;color:rgba(255,255,255,0.75);">DriftPro · MAVI Logistikk</div>
<h1 style="margin:12px 0 0;font-size:26px;line-height:1.25;color:#ffffff;font-weight:700;">%s</h1>
</td></tr>
<tr><td style="padding:32px 32px 24px;">
<p style="margin:0 0 22px;font-size:15px;line-height:1.65;color:#334155;background:#f0faf4;border-left:4px solid #1B5E20;padding:14px 16px;border-radius:0 8px 8px 0;">%s</p>
%s
<div style="text-align:center;margin:30px 0 10px;">
<a href="%s" style="display:inline-block;background:#1B5E20;color:#ffffff !important;text-decoration:none;font-weight:700;font-size:15px;padding:15px 32px;border-radius:10px;box-shadow:0 4px 14px rgba(27,94,32,0.35);">%s</a>
</div>
<p style="margin:18px 0 0;font-size:12px;line-height:1.5;color:#94a3b8;text-align:center;">Logg inn som samarbeidspartner på <a href="https://driftpro.no" style="color:#1B5E20;text-decoration:none;font-weight:600;">driftpro.no</a></p>
</td></tr>
<tr><td style="padding:22px 32px;background:#f8faf9;border-top:1px solid #eef2f0;">
<p style="margin:0;font-size:11px;line-height:1.5;color:#94a3b8;text-align:center;">Automatisk varsel fra DriftPro. Svar ikke på denne e-posten.</p>
</td></tr>
</table>
</td></tr>
</table>
</body>
</html>
$html$,
    public.escape_html(p_heading),
    CASE WHEN coalesce(p_preheader, '') <> '' THEN
      format('<div style="display:none;max-height:0;overflow:hidden;">%s</div>', public.escape_html(p_preheader))
    ELSE '' END,
    public.escape_html(p_heading),
    public.escape_html(p_intro),
    CASE WHEN v_rows <> '' THEN
      '<table role="presentation" width="100%%" cellspacing="0" cellpadding="0" style="margin:0 0 4px;background:#fafbfc;border-radius:10px;padding:4px 12px;">' || v_rows || '</table>'
    ELSE '' END,
    public.escape_html(p_cta_url),
    public.escape_html(p_cta_label)
  );
END;
$$;

-- ── 1. Slå av gammel duplikat-trigger (plain «aa aapne»-mail) ───────────────
CREATE OR REPLACE FUNCTION public.notify_partner_on_route_share()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_partner_on_route_share ON public.partner_route_shares;
DROP TRIGGER IF EXISTS trg_notify_partner_on_route_share_sent ON public.partner_route_shares;

-- ── 2. Oppdatert innhold — ikke nevn avvis ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.build_partner_route_published_email(
  p_unit_code text,
  p_vehicle_reg text,
  p_partner_name text,
  p_shift_name text,
  p_title text,
  p_share_date date,
  p_route_start_at timestamptz
)
RETURNS TABLE(subject text, body_html text, body_plain text)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_unit text;
  v_details jsonb := '[]'::jsonb;
  v_intro text;
  v_heading text;
BEGIN
  v_unit := coalesce(nullif(trim(p_unit_code), ''), 'Bil');

  v_details := jsonb_build_array(
    jsonb_build_object('label', 'Bil / enhet', 'value', v_unit ||
      CASE WHEN coalesce(trim(p_vehicle_reg), '') <> '' THEN ' (' || trim(p_vehicle_reg) || ')' ELSE '' END),
    jsonb_build_object('label', 'Samarbeidspartner', 'value', coalesce(nullif(trim(p_partner_name), ''), 'Din bedrift')),
    jsonb_build_object('label', 'Skift', 'value', nullif(trim(p_shift_name), '')),
    jsonb_build_object('label', 'Rutedato', 'value',
      CASE WHEN p_share_date IS NOT NULL THEN to_char(p_share_date, 'DD.MM.YYYY') ELSE NULL END),
    jsonb_build_object('label', 'Rute', 'value', nullif(trim(p_title), '')),
    jsonb_build_object('label', 'Planlagt start', 'value',
      CASE WHEN p_route_start_at IS NOT NULL THEN
        to_char(p_route_start_at AT TIME ZONE 'Europe/Oslo', 'DD.MM.YYYY HH24:MI')
      ELSE NULL END)
  );

  v_heading := 'Ny rute er klar';
  v_intro := 'En ny rute-PDF er tilgjengelig i partnerportalen. Logg inn for å åpne ruten og godkjenne den.';

  subject := 'Ny rute i DriftPro — ' || v_unit;
  body_html := public.build_driftpro_email_html(
    v_heading,
    v_intro,
    v_details,
    'Åpne ruten i DriftPro',
    'https://driftpro.no',
    v_unit || ' · ' || coalesce(nullif(trim(p_shift_name), ''), 'ny rute')
  );
  body_plain :=
    'Hei!' || E'\n\n'
    || v_intro || E'\n\n'
    || 'Bil / enhet: ' || v_unit
    || CASE WHEN coalesce(trim(p_vehicle_reg), '') <> '' THEN ' (' || trim(p_vehicle_reg) || ')' ELSE '' END || E'\n'
    || 'Samarbeidspartner: ' || coalesce(nullif(trim(p_partner_name), ''), 'Din bedrift') || E'\n'
    || CASE WHEN coalesce(trim(p_shift_name), '') <> '' THEN 'Skift: ' || trim(p_shift_name) || E'\n' ELSE '' END
    || CASE WHEN p_share_date IS NOT NULL THEN 'Rutedato: ' || to_char(p_share_date, 'DD.MM.YYYY') || E'\n' ELSE '' END
    || CASE WHEN coalesce(trim(p_title), '') <> '' THEN 'Rute: ' || trim(p_title) || E'\n' ELSE '' END
    || CASE WHEN p_route_start_at IS NOT NULL THEN
      'Planlagt start: ' || to_char(p_route_start_at AT TIME ZONE 'Europe/Oslo', 'DD.MM.YYYY HH24:MI') || E'\n'
    ELSE '' END
    || E'\nÅpne: https://driftpro.no' || E'\n\n'
    || 'Med vennlig hilsen' || E'\nDriftPro · MAVI Logistikk';
  RETURN NEXT;
END;
$$;

-- ── 3. Én e-post per utsendelse (dedup ved dobbel trigger) ───────────────────
CREATE OR REPLACE FUNCTION public.notify_partner_route_assigned_sms(p_route_share_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  shift_name TEXT;
  driver_msg TEXT;
  owner_msg TEXT;
  email_sub TEXT;
  email_body TEXT;
  n INT := 0;
  driver_phone TEXT;
  owner_only BOOLEAN;
  sent_phones TEXT[] := ARRAY[]::TEXT[];
  v_skip_email BOOLEAN := false;
BEGIN
  SELECT
    prs.*,
    pv.unit_code,
    pv.registration_number AS vehicle_reg,
    p.name AS partner_name,
    p.is_active AS partner_is_active,
    coalesce(p.routes_owner_only, true) AS routes_owner_only
  INTO r
  FROM public.partner_route_shares prs
  LEFT JOIN public.partner_vehicles pv ON pv.id = prs.partner_vehicle_id
  LEFT JOIN public.partners p ON p.id = prs.partner_id
  WHERE prs.id = p_route_share_id;

  IF r IS NULL OR coalesce(r.partner_is_active, false) = false THEN
    RETURN 0;
  END IF;
  IF r.partner_vehicle_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.partner_vehicles pv2
    WHERE pv2.id = r.partner_vehicle_id AND pv2.is_active = true
  ) THEN
    RETURN 0;
  END IF;
  IF coalesce(r.dispatch_status, 'sent') <> 'sent' THEN
    RETURN 0;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.email_outbox e
    WHERE e.reference_type = 'partner_route_shares'
      AND e.reference_id = p_route_share_id
      AND e.category = 'partner_route_share'
      AND e.created_at > now() - interval '10 minutes'
  ) INTO v_skip_email;

  owner_only := coalesce(r.routes_owner_only, true);
  SELECT name INTO shift_name FROM public.fleet_shift_definitions WHERE id = r.shift_id;

  driver_msg := 'Ny rute tildelt ' || coalesce(r.unit_code, '') ||
    CASE WHEN r.vehicle_reg IS NOT NULL AND trim(r.vehicle_reg) <> '' THEN ' (' || trim(r.vehicle_reg) || ')' ELSE '' END ||
    CASE WHEN shift_name IS NOT NULL THEN ' · Skift: ' || shift_name ELSE '' END ||
    '. Logg inn i DriftPro for PDF og godkjenning.';

  owner_msg := 'Ny rute på ' || coalesce(r.unit_code, 'bil') ||
    ' — ' || coalesce(r.partner_name, 'din bedrift') ||
    CASE WHEN shift_name IS NOT NULL THEN ' · ' || shift_name ELSE '' END ||
    '. Logg inn i DriftPro for oversikt og godkjenning.';

  SELECT e.subject, e.body_html
  INTO email_sub, email_body
  FROM public.build_partner_route_published_email(
    r.unit_code,
    r.vehicle_reg,
    r.partner_name,
    shift_name,
    r.title,
    r.share_date,
    r.route_start_at
  ) e;

  IF NOT owner_only THEN
    SELECT public.normalize_phone_no(ppa.phone) INTO driver_phone
    FROM public.partner_portal_accounts ppa
    JOIN public.partners p ON p.id = ppa.partner_id AND p.is_active = true
    WHERE ppa.partner_vehicle_id = r.partner_vehicle_id
      AND ppa.is_active = true
      AND coalesce(ppa.account_kind, 'driver') = 'driver'
      AND ppa.phone IS NOT NULL
    ORDER BY ppa.updated_at DESC NULLS LAST
    LIMIT 1;

    IF driver_phone IS NOT NULL AND NOT (driver_phone = ANY (sent_phones)) THEN
      IF public.queue_partner_sms_if_allowed(
        r.company_id, driver_phone, driver_msg, 'partner_route', 'partner_route',
        'partner_route_shares', r.id, 'Ny rute → sjåfør'
      ) IS NOT NULL THEN
        sent_phones := array_append(sent_phones, driver_phone);
        n := n + 1;
      END IF;
    END IF;
  END IF;

  n := n + public.notify_partner_owner_phones(
    r.company_id, r.partner_id, owner_msg, 'partner_route_owner', 'partner_route_owner',
    'partner_route_shares', r.id, 'Ny rute → bil-eier'
  );

  IF NOT v_skip_email THEN
    n := n + public.notify_partner_owner_emails(
      r.company_id, r.partner_id, email_sub, email_body, 'partner_route_share',
      'partner_route_owner', 'partner_route_shares', r.id, 'Ny rute (e-post HTML)'
    );
  END IF;

  RETURN n;
END;
$$;

COMMENT ON FUNCTION public.notify_partner_on_route_share IS
  'Deaktivert — bruk notify_partner_route_assigned_sms (én HTML-e-post).';
COMMENT ON FUNCTION public.notify_partner_route_assigned_sms IS
  'SMS + maks én HTML-e-post per rute (10 min dedup). Ingen «avvis» i e-post.';
