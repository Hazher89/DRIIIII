-- Fravær godkjent/avvist: ansatt skal alltid få push (og SMS/e-post) når firmakanalen er på.
--
-- Feil funnet:
-- 1) SMS/e-post gikk via profile_event_allows_* som krever assignable_to_employees —
--    absence_decision er «Til ansatt» (ikke abonnerbar for ledere), så vanlige ansatte ble blokkert.
-- 2) Push returnerte stille 0 når ansatt manglet FCM-token (ingen audit).
-- 3) Trigger kun på UPDATE OF status, decision_comment — utvides til hele UPDATE med samme status-sjekk.

CREATE OR REPLACE FUNCTION public.queue_push_to_profile_if_allowed(
  p_company_id UUID,
  p_profile_id UUID,
  p_title TEXT,
  p_body TEXT,
  p_category TEXT,
  p_reference_type TEXT,
  p_reference_id UUID,
  p_setting_key TEXT,
  p_description TEXT DEFAULT NULL,
  p_partner_scope BOOLEAN DEFAULT false,
  p_data JSONB DEFAULT '{}'::jsonb
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d RECORD;
  n INT := 0;
  sent TEXT[] := ARRAY[]::TEXT[];
  v_has_devices BOOLEAN := false;
  v_enabled BOOLEAN;
BEGIN
  IF p_partner_scope THEN
    v_enabled := public.company_partner_push_enabled(p_company_id, p_setting_key);
  ELSE
    v_enabled := public.company_push_enabled(p_company_id, p_setting_key);
  END IF;

  IF NOT v_enabled THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'push', p_category, p_setting_key,
      NULL, p_profile_id, 'skipped', 'company_channel_off',
      coalesce(p_description, left(p_body, 120)), NULL, NULL, NULL, p_reference_type, p_reference_id
    );
    RETURN 0;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.user_push_devices upd
    WHERE upd.profile_id = p_profile_id
      AND upd.is_active = true
      AND nullif(trim(upd.fcm_token), '') IS NOT NULL
  ) INTO v_has_devices;

  FOR d IN
    SELECT DISTINCT ON (upd.fcm_token)
      upd.fcm_token
    FROM public.user_push_devices upd
    WHERE upd.profile_id = p_profile_id
      AND upd.is_active = true
    ORDER BY upd.fcm_token, upd.last_seen_at DESC
  LOOP
    IF d.fcm_token IS NOT NULL AND NOT (d.fcm_token = ANY (sent)) THEN
      IF public.queue_push_if_allowed(
        p_company_id, p_profile_id, d.fcm_token, p_title, p_body,
        p_category, p_reference_type, p_reference_id, p_setting_key, p_description,
        p_partner_scope, p_data
      ) IS NOT NULL THEN
        n := n + 1;
      END IF;
      sent := array_append(sent, d.fcm_token);
    END IF;
  END LOOP;

  -- Legacy profiles.fcm_token kun når ingen aktive enheter er registrert.
  IF NOT v_has_devices THEN
    FOR d IN
      SELECT pr.fcm_token
      FROM public.profiles pr
      WHERE pr.id = p_profile_id
        AND nullif(trim(pr.fcm_token), '') IS NOT NULL
    LOOP
      IF d.fcm_token IS NOT NULL AND NOT (d.fcm_token = ANY (sent)) THEN
        IF public.queue_push_if_allowed(
          p_company_id, p_profile_id, d.fcm_token, p_title, p_body,
          p_category, p_reference_type, p_reference_id, p_setting_key, p_description,
          p_partner_scope, p_data
        ) IS NOT NULL THEN
          n := n + 1;
        END IF;
        sent := array_append(sent, d.fcm_token);
      END IF;
    END LOOP;
  END IF;

  IF n = 0 THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'push', p_category, p_setting_key,
      NULL, p_profile_id, 'skipped', 'no_push_devices',
      'Ingen aktiv push-enhet — logg inn i appen og slå på varsler',
      NULL, NULL, NULL, p_reference_type, p_reference_id
    );
  END IF;

  RETURN n;
END;
$$;

-- Sikre at brukeraksept-hjelpere finnes (kan mangle hvis kun ad-hoc SQL ble kjørt tidligere).
CREATE OR REPLACE FUNCTION public.user_accepts_sms(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT sms_opt_in FROM public.profiles WHERE id = p_user_id),
    true
  );
$$;

CREATE OR REPLACE FUNCTION public.notify_absence_decision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _phone TEXT;
  _email TEXT;
  _status_label TEXT;
  _msg TEXT;
  _push_body TEXT;
  _email_body TEXT;
  _push_title TEXT;
  _sms_id UUID;
  _email_id UUID;
BEGIN
  IF tg_op <> 'UPDATE' THEN
    RETURN new;
  END IF;

  IF old.status IS NOT DISTINCT FROM new.status THEN
    RETURN new;
  END IF;

  IF old.status <> 'ventende'::public.absence_status
     OR new.status NOT IN ('godkjent'::public.absence_status, 'avvist'::public.absence_status) THEN
    RETURN new;
  END IF;

  IF new.user_id IS NULL THEN
    RETURN new;
  END IF;

  _status_label := CASE WHEN new.status = 'godkjent'::public.absence_status THEN 'godkjent' ELSE 'avvist' END;
  _push_title := 'Fravær ' || _status_label;

  _msg :=
    'DriftPro: ' || coalesce(new.type::text, 'fravær') || ' '
    || _status_label || ' '
    || to_char(new.start_date, 'DD.MM') || '–' || to_char(new.end_date, 'DD.MM') || '.';

  _push_body := _msg
    || CASE
         WHEN coalesce(new.decision_comment, '') <> ''
         THEN ' ' || left(new.decision_comment, 120)
         ELSE ''
       END;

  _email_body :=
    'Din fraværssøknad er ' || _status_label || '.' || E'\n\n'
    || 'Type: ' || coalesce(new.type::text, 'ukjent') || E'\n'
    || 'Periode: ' || to_char(new.start_date, 'DD.MM.YYYY')
    || ' – ' || to_char(new.end_date, 'DD.MM.YYYY')
    || CASE WHEN coalesce(new.decision_comment, '') <> '' THEN E'\n\nKommentar: ' || new.decision_comment ELSE '' END;

  SELECT
    coalesce(phone_normalized, phone),
    email
  INTO _phone, _email
  FROM public.profiles
  WHERE id = new.user_id;

  -- Push: kun firmakanal + FCM-token (ikke abonnementsliste — mottaker er alltid søkeren).
  PERFORM public.queue_push_to_profile_if_allowed(
    new.company_id,
    new.user_id,
    _push_title,
    _push_body,
    'absence',
    'absences',
    new.id,
    'absence_decision',
    'Fravær beslutning (push)',
    false,
    jsonb_build_object(
      'type', 'absence_decision',
      'reference_type', 'absences',
      'reference_id', new.id::text,
      'category', 'absence',
      'status', new.status::text
    )
  );

  -- SMS: firmakanal + brukeraksept (ikke profile_receives — den er for leder-abonnementer).
  IF public.company_sms_enabled(new.company_id, 'absence_decision')
     AND public.user_accepts_sms(new.user_id)
     AND public.user_effective_notify_channel(new.user_id)
         NOT IN ('none'::public.notification_channel, 'email'::public.notification_channel)
     AND coalesce(_phone, '') <> '' THEN
    _sms_id := public.queue_sms(
      new.company_id,
      _phone,
      _msg,
      'absence',
      'absences',
      new.id,
      new.user_id,
      auth.uid()
    );
    IF _sms_id IS NOT NULL THEN
      PERFORM public.log_notification_audit(
        new.company_id, 'sms', 'absence', 'absence_decision',
        _phone, new.user_id, 'queued', NULL,
        'Fravær beslutning (SMS)', _sms_id, NULL, NULL, 'absences', new.id
      );
    END IF;
  ELSIF NOT public.company_sms_enabled(new.company_id, 'absence_decision') THEN
    PERFORM public.log_notification_audit(
      new.company_id, 'sms', 'absence', 'absence_decision',
      coalesce(_phone, ''), new.user_id, 'skipped', 'company_channel_off',
      'Fravær beslutning (SMS)', NULL, NULL, NULL, 'absences', new.id
    );
  END IF;

  -- E-post: samme logikk som SMS (mottaker = søker).
  IF public.company_email_enabled(new.company_id, 'absence_decision')
     AND public.user_accepts_email(new.user_id)
     AND public.user_effective_notify_channel(new.user_id)
         NOT IN ('none'::public.notification_channel, 'sms'::public.notification_channel)
     AND coalesce(_email, '') <> '' THEN
    _email_id := public.queue_email(
      new.company_id,
      _email,
      _push_title,
      _email_body,
      'absence',
      'absences',
      new.id,
      'Fravær beslutning (e-post)',
      new.user_id,
      auth.uid()
    );
    IF _email_id IS NOT NULL THEN
      PERFORM public.log_notification_audit(
        new.company_id, 'email', 'absence', 'absence_decision',
        _email, new.user_id, 'queued', NULL,
        'Fravær beslutning (e-post)', _email_id, NULL, NULL, 'absences', new.id
      );
    END IF;
  ELSIF NOT public.company_email_enabled(new.company_id, 'absence_decision') THEN
    PERFORM public.log_notification_audit(
      new.company_id, 'email', 'absence', 'absence_decision',
      coalesce(_email, ''), new.user_id, 'skipped', 'company_channel_off',
      'Fravær beslutning (e-post)', NULL, NULL, NULL, 'absences', new.id
    );
  END IF;

  RETURN new;
END;
$$;

-- Kjør ved alle status-oppdateringer (ikke bare når decision_comment er i SET-listen).
DROP TRIGGER IF EXISTS trg_notify_absence_decision ON public.absences;
CREATE TRIGGER trg_notify_absence_decision
  AFTER UPDATE ON public.absences
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_absence_decision();

-- Unngå dobbel SMS/e-post fra eldre trigger-navn (hvis de fortsatt finnes i prod).
DROP TRIGGER IF EXISTS trg_notify_absence_decision_sms ON public.absences;
DROP TRIGGER IF EXISTS trg_notify_absence_decision_email ON public.absences;

-- Sørg for at firmakanalen har push på for absence_decision der rad mangler.
DO $$
DECLARE
  c RECORD;
BEGIN
  FOR c IN SELECT id FROM public.companies LOOP
    PERFORM public.ensure_notification_event_channels(c.id);
  END LOOP;
END $$;

UPDATE public.company_notification_event_channels
SET push_enabled = true
WHERE event_id = 'absence_decision'
  AND push_enabled IS DISTINCT FROM true;

COMMENT ON FUNCTION public.notify_absence_decision IS
  'Ved godkjent/avvist: push + SMS + e-post direkte til søker (ikke leder-abonnement).';
