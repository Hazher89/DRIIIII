-- Push til Hazher ved ny enhet / innlogging (ansatt + partner).
-- Ingen app-endring: bruker eksisterende upsert_push_device + auth.users last_sign_in.

CREATE TABLE IF NOT EXISTS public.admin_session_alert_dedupe (
  subject_profile_id UUID NOT NULL,
  alert_kind TEXT NOT NULL,
  last_alerted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (subject_profile_id, alert_kind)
);

COMMENT ON TABLE public.admin_session_alert_dedupe IS
  'Unngår spam av admin-push ved gjentatt token-refresh / innlogging.';

CREATE OR REPLACE FUNCTION public.hazher_admin_profile_ids()
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id
  FROM public.profiles p
  WHERE p.is_active IS DISTINCT FROM false
    AND (
      p.id = '59c201f6-b9e0-4454-ad79-e25db7df8396'::uuid
      OR lower(coalesce(p.email, '')) = 'hazher@mavilogistikk.no'
      OR coalesce(p.employee_number, '') = '25'
    );
$$;

CREATE OR REPLACE FUNCTION public.notify_hazher_session_alert(
  p_subject_profile_id UUID,
  p_alert_kind TEXT,
  p_title TEXT,
  p_body TEXT,
  p_dedupe_minutes INT DEFAULT 20
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_kind TEXT := lower(trim(coalesce(p_alert_kind, 'login')));
  v_admin UUID;
  d RECORD;
  n INT := 0;
  v_company UUID := '00000000-0000-0000-0000-000000000000'::uuid;
  v_push_id UUID;
  v_last TIMESTAMPTZ;
BEGIN
  IF p_subject_profile_id IS NULL THEN
    RETURN 0;
  END IF;

  -- Ikke varsle når Hazher selv logger inn / registrerer enhet.
  IF p_subject_profile_id IN (SELECT public.hazher_admin_profile_ids()) THEN
    RETURN 0;
  END IF;

  SELECT last_alerted_at INTO v_last
  FROM public.admin_session_alert_dedupe
  WHERE subject_profile_id = p_subject_profile_id
    AND alert_kind = v_kind;

  IF v_last IS NOT NULL
     AND v_last > now() - make_interval(mins => greatest(coalesce(p_dedupe_minutes, 20), 1)) THEN
    RETURN 0;
  END IF;

  INSERT INTO public.admin_session_alert_dedupe (subject_profile_id, alert_kind, last_alerted_at)
  VALUES (p_subject_profile_id, v_kind, now())
  ON CONFLICT (subject_profile_id, alert_kind) DO UPDATE
    SET last_alerted_at = now();

  SELECT company_id INTO v_company
  FROM public.profiles
  WHERE id = p_subject_profile_id;

  IF v_company IS NULL THEN
    v_company := '00000000-0000-0000-0000-000000000000'::uuid;
  END IF;

  FOR v_admin IN SELECT public.hazher_admin_profile_ids()
  LOOP
    FOR d IN
      SELECT DISTINCT ON (upd.fcm_token) upd.fcm_token
      FROM public.user_push_devices upd
      WHERE upd.profile_id = v_admin
        AND upd.is_active = true
        AND nullif(trim(upd.fcm_token), '') IS NOT NULL
      ORDER BY upd.fcm_token, upd.last_seen_at DESC
    LOOP
      INSERT INTO public.push_outbox (
        company_id, profile_id, fcm_token, title, body, data, category,
        reference_type, reference_id, description
      ) VALUES (
        v_company,
        v_admin,
        d.fcm_token,
        left(trim(p_title), 120),
        left(trim(p_body), 500),
        jsonb_build_object(
          'type', 'admin_session_alert',
          'kind', v_kind,
          'subject_profile_id', p_subject_profile_id::text
        ),
        'admin_session',
        'profiles',
        p_subject_profile_id,
        'Admin: ' || v_kind
      )
      RETURNING id INTO v_push_id;
      n := n + 1;
    END LOOP;

    -- Legacy token fallback
    IF n = 0 THEN
      FOR d IN
        SELECT nullif(trim(pr.fcm_token), '') AS fcm_token
        FROM public.profiles pr
        WHERE pr.id = v_admin
          AND nullif(trim(pr.fcm_token), '') IS NOT NULL
      LOOP
        INSERT INTO public.push_outbox (
          company_id, profile_id, fcm_token, title, body, data, category,
          reference_type, reference_id, description
        ) VALUES (
          v_company,
          v_admin,
          d.fcm_token,
          left(trim(p_title), 120),
          left(trim(p_body), 500),
          jsonb_build_object(
            'type', 'admin_session_alert',
            'kind', v_kind,
            'subject_profile_id', p_subject_profile_id::text
          ),
          'admin_session',
          'profiles',
          p_subject_profile_id,
          'Admin: ' || v_kind
        );
        n := n + 1;
      END LOOP;
    END IF;
  END LOOP;

  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_push_device(
  p_fcm_token TEXT,
  p_platform TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  tok TEXT := trim(coalesce(p_fcm_token, ''));
  plat TEXT := nullif(trim(coalesce(p_platform, '')), '');
  v_existed BOOLEAN := false;
  v_was_active BOOLEAN := false;
  v_prev_seen TIMESTAMPTZ;
  v_name TEXT;
  v_email TEXT;
  v_role TEXT;
  v_partner UUID;
  v_kind TEXT;
  v_label TEXT;
  v_platform_label TEXT;
BEGIN
  IF uid IS NULL OR tok = '' THEN
    RETURN;
  END IF;

  SELECT true, upd.is_active, upd.last_seen_at
    INTO v_existed, v_was_active, v_prev_seen
  FROM public.user_push_devices upd
  WHERE upd.profile_id = uid
    AND upd.fcm_token = tok;

  v_existed := coalesce(v_existed, false);

  UPDATE public.user_push_devices
  SET is_active = false
  WHERE fcm_token = tok
    AND profile_id IS DISTINCT FROM uid
    AND is_active = true;

  UPDATE public.profiles
  SET fcm_token = NULL
  WHERE fcm_token = tok
    AND id IS DISTINCT FROM uid;

  INSERT INTO public.user_push_devices (profile_id, fcm_token, platform, last_seen_at, is_active)
  VALUES (uid, tok, plat, now(), true)
  ON CONFLICT (profile_id, fcm_token) DO UPDATE SET
    platform = coalesce(excluded.platform, public.user_push_devices.platform),
    last_seen_at = now(),
    is_active = true;

  UPDATE public.profiles
  SET fcm_token = tok
  WHERE id = uid;

  SELECT
    coalesce(nullif(trim(p.full_name), ''), 'Ukjent'),
    coalesce(nullif(trim(p.email), ''), ''),
    coalesce(p.role::text, 'ansatt'),
    p.partner_id
  INTO v_name, v_email, v_role, v_partner
  FROM public.profiles p
  WHERE p.id = uid;

  IF v_role = 'samarbeidspartner' OR v_partner IS NOT NULL THEN
    v_kind := 'Partner';
  ELSE
    v_kind := 'Ansatt';
  END IF;

  v_platform_label := CASE lower(coalesce(plat, ''))
    WHEN 'ios' THEN 'iPhone/iPad'
    WHEN 'android' THEN 'Android'
    ELSE coalesce(plat, 'app')
  END;

  v_label := v_name;
  IF v_email <> '' THEN
    v_label := v_label || ' (' || v_email || ')';
  END IF;

  -- Ny enhet / ny token for denne brukeren
  IF NOT v_existed THEN
    PERFORM public.notify_hazher_session_alert(
      uid,
      'new_device',
      'Ny enhet · ' || v_kind,
      v_label || ' lastet DriftPro på ' || v_platform_label || '.',
      5
    );
  -- Innlogging / retur på kjent enhet (etter pause, eller reaktivering)
  ELSIF coalesce(v_was_active, false) = false
     OR v_prev_seen IS NULL
     OR v_prev_seen < now() - interval '2 hours' THEN
    PERFORM public.notify_hazher_session_alert(
      uid,
      'login',
      'Innlogging · ' || v_kind,
      v_label || ' logget inn (' || v_platform_label || ').',
      20
    );
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_push_device(TEXT, TEXT) TO authenticated;

-- Innlogging også uten push-token (web / før FCM er klar)
CREATE OR REPLACE FUNCTION public.trg_auth_user_login_alert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name TEXT;
  v_email TEXT;
  v_role TEXT;
  v_partner UUID;
  v_kind TEXT;
  v_label TEXT;
BEGIN
  IF NEW.last_sign_in_at IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.last_sign_in_at IS NOT NULL
     AND NEW.last_sign_in_at IS NOT DISTINCT FROM OLD.last_sign_in_at THEN
    RETURN NEW;
  END IF;

  SELECT
    coalesce(nullif(trim(p.full_name), ''), 'Ukjent'),
    coalesce(nullif(trim(p.email), ''), coalesce(NEW.email, '')),
    coalesce(p.role::text, 'ansatt'),
    p.partner_id
  INTO v_name, v_email, v_role, v_partner
  FROM public.profiles p
  WHERE p.id = NEW.id;

  IF NOT FOUND THEN
    v_name := split_part(coalesce(NEW.email, 'bruker'), '@', 1);
    v_email := coalesce(NEW.email, '');
    v_role := 'ansatt';
  END IF;

  IF v_role = 'samarbeidspartner' OR v_partner IS NOT NULL THEN
    v_kind := 'Partner';
  ELSE
    v_kind := 'Ansatt';
  END IF;

  v_label := v_name;
  IF coalesce(v_email, '') <> '' THEN
    v_label := v_label || ' (' || v_email || ')';
  END IF;

  PERFORM public.notify_hazher_session_alert(
    NEW.id,
    'login',
    'Innlogging · ' || v_kind,
    v_label || ' logget inn.',
    20
  );

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auth_user_login_alert ON auth.users;
CREATE TRIGGER trg_auth_user_login_alert
  AFTER UPDATE OF last_sign_in_at ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_auth_user_login_alert();

COMMENT ON FUNCTION public.notify_hazher_session_alert IS
  'Sender push til Hazher ved ny enhet eller innlogging (ansatt/partner).';
COMMENT ON FUNCTION public.upsert_push_device(TEXT, TEXT) IS
  'Registrerer FCM-token og varsler Hazher ved ny enhet / retur-innlogging.';
