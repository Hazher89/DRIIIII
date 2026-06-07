-- HMS: lagring, varsler, ROS↔avvik-kobling, SJA-signering og offline-sync RPC.

-- ── Lagring ─────────────────────────────────────────────────────────────────

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  (
    'avvik',
    'avvik',
    true,
    52428800,
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/quicktime']::text[]
  ),
  (
    'sja',
    'sja',
    true,
    20971520,
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']::text[]
  ),
  (
    'risk-assessments',
    'risk-assessments',
    true,
    20971520,
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']::text[]
  )
ON CONFLICT (id) DO UPDATE
SET
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS avvik_public_read ON storage.objects;
CREATE POLICY avvik_public_read ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'avvik');

DROP POLICY IF EXISTS avvik_auth_upload ON storage.objects;
CREATE POLICY avvik_auth_upload ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'avvik'
    AND (storage.foldername(name))[1] = public.get_user_company_id()::text
  );

DROP POLICY IF EXISTS avvik_auth_update ON storage.objects;
CREATE POLICY avvik_auth_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'avvik'
    AND (storage.foldername(name))[1] = public.get_user_company_id()::text
  );

DROP POLICY IF EXISTS avvik_auth_delete ON storage.objects;
CREATE POLICY avvik_auth_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'avvik'
    AND (storage.foldername(name))[1] = public.get_user_company_id()::text
  );

DROP POLICY IF EXISTS sja_public_read ON storage.objects;
CREATE POLICY sja_public_read ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'sja');

DROP POLICY IF EXISTS sja_auth_upload ON storage.objects;
CREATE POLICY sja_auth_upload ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'sja'
    AND (storage.foldername(name))[1] = public.get_user_company_id()::text
  );

DROP POLICY IF EXISTS risk_assessments_public_read ON storage.objects;
CREATE POLICY risk_assessments_public_read ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'risk-assessments');

DROP POLICY IF EXISTS risk_assessments_auth_upload ON storage.objects;
CREATE POLICY risk_assessments_auth_upload ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'risk-assessments'
    AND (storage.foldername(name))[1] = public.get_user_company_id()::text
  );

-- ── Push-varsel helper ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.hms_push_notification(
  p_user_id uuid,
  p_company_id uuid,
  p_title text,
  p_body text,
  p_data jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.notifications (user_id, company_id, title, body, type, data)
  VALUES (p_user_id, p_company_id, p_title, p_body, 'begge', p_data);
END;
$$;

-- ── Varsle nærmeste leder ved ny HMS-registrering ───────────────────────────

CREATE OR REPLACE FUNCTION public.hms_notify_nearest_leaders(
  p_company_id uuid,
  p_department_id uuid,
  p_reporter_id uuid,
  p_title text,
  p_category text,
  p_reference_type text,
  p_reference_id uuid,
  p_setting_key text DEFAULT 'general'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  leader_id uuid;
  reporter_name text;
  dept_name text;
  msg text;
  notified boolean := false;
BEGIN
  SELECT coalesce(full_name, 'Ansatt') INTO reporter_name
  FROM public.profiles WHERE id = p_reporter_id;

  SELECT name INTO dept_name
  FROM public.departments WHERE id = p_department_id;

  msg :=
    'DriftPro HMS: ' || coalesce(p_title, 'Ny registrering')
    || '. Fra ' || reporter_name
    || coalesce(' (' || dept_name || ')', '')
    || '. Åpne appen for detaljer.';

  IF p_department_id IS NOT NULL THEN
    FOR leader_id IN
      SELECT public.hms_resolve_department_leader_ids(p_department_id)
    LOOP
      IF leader_id IS NOT NULL AND leader_id IS DISTINCT FROM p_reporter_id THEN
        PERFORM public.queue_sms_if_allowed(
          p_company_id,
          leader_id,
          NULL,
          msg,
          p_category,
          p_reference_type,
          p_reference_id,
          p_setting_key
        );

        PERFORM public.hms_push_notification(
          leader_id,
          p_company_id,
          'Ny HMS-registrering',
          msg,
          jsonb_build_object(
            'reference_type', p_reference_type,
            'reference_id', p_reference_id,
            'category', p_category
          )
        );

        notified := true;
      END IF;
    END LOOP;
  END IF;

  IF NOT notified THEN
    FOR leader_id IN
      SELECT id
      FROM public.profiles
      WHERE company_id = p_company_id
        AND is_active = true
        AND is_approved = true
        AND role IN ('admin', 'superadmin')
        AND id IS DISTINCT FROM p_reporter_id
    LOOP
      PERFORM public.queue_sms_if_allowed(
        p_company_id,
        leader_id,
        NULL,
        msg,
        p_category,
        p_reference_type,
        p_reference_id,
        p_setting_key
      );

      PERFORM public.hms_push_notification(
        leader_id,
        p_company_id,
        'Ny HMS-registrering',
        msg,
        jsonb_build_object(
          'reference_type', p_reference_type,
          'reference_id', p_reference_id,
          'category', p_category
        )
      );
    END LOOP;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.hms_notify_on_ticket_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.assigned_to IS NULL THEN
    PERFORM public.hms_notify_nearest_leaders(
      NEW.company_id,
      NEW.department_id,
      NEW.reported_by,
      coalesce(NEW.title, 'Nytt avvik'),
      'hms_ticket_new',
      'tickets',
      NEW.id,
      'hms'
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_hms_notify_on_ticket_insert ON public.tickets;
CREATE TRIGGER trg_hms_notify_on_ticket_insert
  AFTER INSERT ON public.tickets
  FOR EACH ROW
  EXECUTE FUNCTION public.hms_notify_on_ticket_insert();

CREATE OR REPLACE FUNCTION public.hms_notify_on_risk_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
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
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_hms_notify_on_risk_insert ON public.risk_assessments;
CREATE TRIGGER trg_hms_notify_on_risk_insert
  AFTER INSERT ON public.risk_assessments
  FOR EACH ROW
  EXECUTE FUNCTION public.hms_notify_on_risk_insert();

CREATE OR REPLACE FUNCTION public.hms_notify_on_sja_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
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
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_hms_notify_on_sja_insert ON public.sja_forms;
CREATE TRIGGER trg_hms_notify_on_sja_insert
  AFTER INSERT ON public.sja_forms
  FOR EACH ROW
  EXECUTE FUNCTION public.hms_notify_on_sja_insert();

-- ── ROS ↔ Avvik: 3+ like avvik → flagg ROS ──────────────────────────────────

CREATE OR REPLACE FUNCTION public.hms_process_avvik_ros_signal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_category text;
  v_count int;
  v_sample_ids uuid[];
  v_signal_id uuid;
  v_leader_id uuid;
  v_msg text;
BEGIN
  v_category := nullif(trim(coalesce(NEW.category, '')), '');
  IF v_category IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT count(*), array_agg(id ORDER BY created_at DESC)
  INTO v_count, v_sample_ids
  FROM public.tickets t
  WHERE t.company_id = NEW.company_id
    AND lower(trim(t.category)) = lower(v_category)
    AND t.created_at >= (now() - interval '30 days')
    AND t.status <> 'lukket'::public.ticket_status;

  IF v_count < 3 THEN
    RETURN NEW;
  END IF;

  UPDATE public.hms_ros_avvik_signals sig
  SET
    ticket_count = v_count,
    sample_ticket_ids = coalesce(v_sample_ids[1:5], '{}'),
    department_id = NEW.department_id,
    updated_at = now()
  WHERE sig.company_id = NEW.company_id
    AND lower(sig.ticket_category) = lower(v_category)
    AND sig.status = 'active'
  RETURNING sig.id INTO v_signal_id;

  IF v_signal_id IS NULL THEN
    INSERT INTO public.hms_ros_avvik_signals (
      company_id,
      department_id,
      ticket_category,
      ticket_count,
      sample_ticket_ids,
      status
    )
    VALUES (
      NEW.company_id,
      NEW.department_id,
      v_category,
      v_count,
      coalesce(v_sample_ids[1:5], '{}'),
      'active'
    )
    RETURNING id INTO v_signal_id;
  END IF;

  UPDATE public.risk_assessments ra
  SET
    avvik_boosted = true,
    avvik_signal_count = v_count,
    avvik_last_signal_at = now(),
    linked_ticket_category = v_category,
    initial_probability = LEAST(5, coalesce(ra.initial_probability, ra.probability) + 1),
    updated_at = now()
  WHERE ra.company_id = NEW.company_id
    AND ra.status = 'aktiv'
    AND (
      lower(coalesce(ra.linked_ticket_category, '')) = lower(v_category)
      OR lower(coalesce(ra.scenario_category, '')) = lower(v_category)
      OR lower(ra.title) LIKE '%' || lower(v_category) || '%'
    );

  v_msg :=
    'DriftPro ROS: ' || v_count || ' avvik av type «' || v_category
    || '» på 30 dager. Revider ROS-analysen.';

  IF NEW.department_id IS NOT NULL THEN
    FOR v_leader_id IN
      SELECT * FROM public.hms_resolve_department_leader_ids(NEW.department_id)
    LOOP
      PERFORM public.queue_sms_if_allowed(
        NEW.company_id,
        v_leader_id,
        NULL,
        v_msg,
        'hms_ros_avvik_signal',
        'hms_ros_avvik_signals',
        coalesce(v_signal_id, NEW.id),
        'hms'
      );

      PERFORM public.hms_push_notification(
        v_leader_id,
        NEW.company_id,
        'ROS må revideres',
        v_msg,
        jsonb_build_object(
          'ticket_category', v_category,
          'ticket_count', v_count,
          'signal_id', v_signal_id
        )
      );
    END LOOP;
  END IF;

  FOR v_leader_id IN
    SELECT id
    FROM public.profiles
    WHERE company_id = NEW.company_id
      AND role IN ('admin', 'superadmin')
      AND is_active = true
  LOOP
    PERFORM public.queue_sms_if_allowed(
      NEW.company_id,
      v_leader_id,
      NULL,
      v_msg,
      'hms_ros_avvik_signal',
      'hms_ros_avvik_signals',
      coalesce(v_signal_id, NEW.id),
      'hms'
    );

    PERFORM public.hms_push_notification(
      v_leader_id,
      NEW.company_id,
      'ROS må revideres',
      v_msg,
      jsonb_build_object(
        'ticket_category', v_category,
        'ticket_count', v_count,
        'signal_id', v_signal_id
      )
    );
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_hms_process_avvik_ros_signal ON public.tickets;
CREATE TRIGGER trg_hms_process_avvik_ros_signal
  AFTER INSERT ON public.tickets
  FOR EACH ROW
  EXECUTE FUNCTION public.hms_process_avvik_ros_signal();

-- Unngå duplikate aktive signaler per kategori
CREATE UNIQUE INDEX IF NOT EXISTS idx_hms_ros_avvik_signals_unique_active
  ON public.hms_ros_avvik_signals (company_id, lower(ticket_category))
  WHERE status = 'active';

-- ── SJA: signering og status ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.hms_refresh_sja_signature_state(p_sja_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sja public.sja_forms%ROWTYPE;
  v_signed int;
BEGIN
  SELECT * INTO v_sja FROM public.sja_forms WHERE id = p_sja_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT count(*) INTO v_signed
  FROM public.hms_sja_signatures
  WHERE sja_id = p_sja_id;

  UPDATE public.sja_forms
  SET
    signed_by = (
      SELECT coalesce(array_agg(profile_id ORDER BY signed_at), '{}')
      FROM public.hms_sja_signatures
      WHERE sja_id = p_sja_id
    ),
    status = CASE
      WHEN v_signed >= greatest(v_sja.required_signatures, 1)
        AND status IN ('utkast', 'venter_signatur', 'signert')
        THEN 'signert'::public.sja_status
      WHEN v_signed > 0 AND status = 'utkast'
        THEN 'venter_signatur'::public.sja_status
      ELSE status
    END,
    updated_at = now()
  WHERE id = p_sja_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.hms_register_sja_signature(
  p_sja_id uuid,
  p_method public.hms_signature_method DEFAULT 'digital',
  p_signature_url text DEFAULT NULL,
  p_pin_verified boolean DEFAULT false,
  p_device_info jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sja public.sja_forms%ROWTYPE;
  v_sig_id uuid;
BEGIN
  SELECT * INTO v_sja FROM public.sja_forms WHERE id = p_sja_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'SJA ikke funnet';
  END IF;

  IF v_sja.company_id <> public.get_user_company_id() THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  INSERT INTO public.hms_sja_signatures (
    sja_id,
    company_id,
    profile_id,
    method,
    signature_url,
    pin_verified,
    device_info
  )
  VALUES (
    p_sja_id,
    v_sja.company_id,
    auth.uid(),
    p_method,
    p_signature_url,
    p_pin_verified,
    p_device_info
  )
  ON CONFLICT (sja_id, profile_id) DO UPDATE
  SET
    signed_at = now(),
    method = EXCLUDED.method,
    signature_url = coalesce(EXCLUDED.signature_url, public.hms_sja_signatures.signature_url),
    pin_verified = EXCLUDED.pin_verified,
    device_info = EXCLUDED.device_info
  RETURNING id INTO v_sig_id;

  PERFORM public.hms_refresh_sja_signature_state(p_sja_id);
  RETURN v_sig_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.hms_start_sja_work(p_sja_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sja public.sja_forms%ROWTYPE;
  v_signed int;
BEGIN
  SELECT * INTO v_sja FROM public.sja_forms WHERE id = p_sja_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'SJA ikke funnet';
  END IF;

  SELECT count(*) INTO v_signed FROM public.hms_sja_signatures WHERE sja_id = p_sja_id;

  IF v_signed < greatest(v_sja.required_signatures, 1) THEN
    RAISE EXCEPTION 'Alle påkrevde signaturer mangler (%/%).', v_signed, v_sja.required_signatures;
  END IF;

  IF v_sja.valid_until IS NOT NULL AND v_sja.valid_until < now() THEN
    RAISE EXCEPTION 'SJA har utløpt — opprett ny vurdering.';
  END IF;

  UPDATE public.sja_forms
  SET
    status = 'i_gang'::public.sja_status,
    work_started_at = coalesce(work_started_at, now()),
    valid_from = coalesce(valid_from, now()),
    valid_until = coalesce(
      valid_until,
      now() + make_interval(hours => greatest(active_window_hours, 1))
    ),
    updated_at = now()
  WHERE id = p_sja_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.hms_check_sja_expiry()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec record;
BEGIN
  FOR rec IN
    SELECT s.*
    FROM public.sja_forms s
    WHERE s.status = 'i_gang'::public.sja_status
      AND s.valid_until IS NOT NULL
      AND s.valid_until < now()
      AND s.expired_notified_at IS NULL
  LOOP
    UPDATE public.sja_forms
    SET
      status = 'utlopt'::public.sja_status,
      expired_notified_at = now(),
      updated_at = now()
    WHERE id = rec.id;

    PERFORM public.hms_notify_nearest_leaders(
      rec.company_id,
      rec.department_id,
      rec.created_by,
      'SJA utløpt — ny vurdering kreves: ' || rec.title,
      'hms_sja_expired',
      'sja_forms',
      rec.id,
      'hms'
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.hms_after_sja_signature()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.hms_refresh_sja_signature_state(NEW.sja_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_hms_after_sja_signature ON public.hms_sja_signatures;
CREATE TRIGGER trg_hms_after_sja_signature
  AFTER INSERT OR UPDATE ON public.hms_sja_signatures
  FOR EACH ROW
  EXECUTE FUNCTION public.hms_after_sja_signature();

-- ── Offline sync RPC ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.hms_enqueue_offline_sync(
  p_entity_type text,
  p_client_id uuid,
  p_operation text,
  p_payload jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_company_id uuid;
BEGIN
  SELECT company_id INTO v_company_id
  FROM public.profiles
  WHERE id = auth.uid();

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Mangler company_id';
  END IF;

  INSERT INTO public.hms_offline_sync_queue (
    company_id,
    user_id,
    entity_type,
    client_id,
    operation,
    payload
  )
  VALUES (
    v_company_id,
    auth.uid(),
    p_entity_type,
    p_client_id,
    p_operation,
    p_payload
  )
  ON CONFLICT (user_id, entity_type, client_id, operation) DO UPDATE
  SET
    payload = EXCLUDED.payload,
    status = 'pending',
    retry_count = public.hms_offline_sync_queue.retry_count,
    last_error = NULL,
    created_at = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.hms_mark_offline_synced(p_queue_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.hms_offline_sync_queue
  SET status = 'synced', synced_at = now(), last_error = NULL
  WHERE id = p_queue_id AND user_id = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION public.hms_push_notification TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.hms_notify_nearest_leaders TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.hms_register_sja_signature TO authenticated;
GRANT EXECUTE ON FUNCTION public.hms_start_sja_work TO authenticated;
GRANT EXECUTE ON FUNCTION public.hms_enqueue_offline_sync TO authenticated;
GRANT EXECUTE ON FUNCTION public.hms_mark_offline_synced TO authenticated;
GRANT EXECUTE ON FUNCTION public.hms_check_sja_expiry TO service_role;

-- Cron for SJA-utløp (kjøres av pg_cron / Edge Function scheduler)
DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname = 'hms_check_sja_expiry';

    PERFORM cron.schedule(
      'hms_check_sja_expiry',
      '*/15 * * * *',
      $$SELECT public.hms_check_sja_expiry();$$
    );
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
$cron$;
