-- Leiebil-sporing: arkiv per dag + rikere samples for kart/presisjon.

ALTER TABLE public.drive_monitor_sessions
  ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS archive_date DATE,
  ADD COLUMN IF NOT EXISTS max_speed_kmh NUMERIC,
  ADD COLUMN IF NOT EXISTS avg_speed_kmh NUMERIC;

ALTER TABLE public.drive_monitor_samples
  ADD COLUMN IF NOT EXISTS accuracy_m NUMERIC,
  ADD COLUMN IF NOT EXISTS altitude_m NUMERIC,
  ADD COLUMN IF NOT EXISTS turn_rate_deg_s NUMERIC;

CREATE INDEX IF NOT EXISTS idx_drive_monitor_sessions_archive
  ON public.drive_monitor_sessions (company_id, archive_date DESC, is_archived);

COMMENT ON COLUMN public.drive_monitor_sessions.is_archived IS
  'Tidligere dager arkiveres automatisk; kan åpnes i hub med datovalg.';

-- Avslutt/arkiver gårsdagens og eldre sesjoner (aktive overnight holdes til de ender).
CREATE OR REPLACE FUNCTION public.archive_drive_monitor_previous_days(
  p_company_id UUID DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID := coalesce(p_company_id, public.get_user_company_id());
  n INT := 0;
BEGIN
  IF auth.uid() IS NULL OR v_company IS NULL THEN
    RETURN 0;
  END IF;
  IF NOT public.can_manage_drive_monitor(v_company) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  -- End ended sessions from previous calendar days.
  UPDATE public.drive_monitor_sessions s
  SET
    is_archived = true,
    archive_date = coalesce(archive_date, (started_at AT TIME ZONE 'Europe/Oslo')::date),
    ended_at = coalesce(ended_at, now()),
    status = CASE WHEN status = 'active' THEN 'ended' ELSE status END
  WHERE s.company_id = v_company
    AND s.is_archived = false
    AND (s.started_at AT TIME ZONE 'Europe/Oslo')::date < (now() AT TIME ZONE 'Europe/Oslo')::date
    AND (
      s.status = 'ended'
      OR s.ended_at IS NOT NULL
      OR s.started_at < now() - interval '18 hours'
    );

  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.archive_drive_monitor_previous_days(UUID) TO authenticated;

-- Hub: hent samples + events for kart (live eller arkivdato).
CREATE OR REPLACE FUNCTION public.get_drive_monitor_map_payload(
  p_company_id UUID,
  p_session_id UUID DEFAULT NULL,
  p_archive_date DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sessions JSONB;
  v_samples JSONB;
  v_events JSONB;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_view_drive_monitor(p_company_id) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY s.started_at DESC), '[]'::jsonb)
  INTO v_sessions
  FROM public.drive_monitor_sessions s
  WHERE s.company_id = p_company_id
    AND (
      (p_session_id IS NOT NULL AND s.id = p_session_id)
      OR (
        p_session_id IS NULL
        AND p_archive_date IS NULL
        AND s.status = 'active'
      )
      OR (
        p_session_id IS NULL
        AND p_archive_date IS NOT NULL
        AND coalesce(s.archive_date, (s.started_at AT TIME ZONE 'Europe/Oslo')::date) = p_archive_date
      )
    );

  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.recorded_at), '[]'::jsonb)
  INTO v_samples
  FROM (
    SELECT sm.*
    FROM public.drive_monitor_samples sm
    JOIN public.drive_monitor_sessions s ON s.id = sm.session_id
    WHERE sm.company_id = p_company_id
      AND (
        (p_session_id IS NOT NULL AND sm.session_id = p_session_id)
        OR (
          p_session_id IS NULL
          AND p_archive_date IS NULL
          AND s.status = 'active'
        )
        OR (
          p_session_id IS NULL
          AND p_archive_date IS NOT NULL
          AND coalesce(s.archive_date, (s.started_at AT TIME ZONE 'Europe/Oslo')::date) = p_archive_date
        )
      )
    ORDER BY sm.recorded_at
    LIMIT 8000
  ) x;

  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.recorded_at), '[]'::jsonb)
  INTO v_events
  FROM (
    SELECT ev.*
    FROM public.drive_monitor_events ev
    JOIN public.drive_monitor_sessions s ON s.id = ev.session_id
    WHERE ev.company_id = p_company_id
      AND (
        (p_session_id IS NOT NULL AND ev.session_id = p_session_id)
        OR (
          p_session_id IS NULL
          AND p_archive_date IS NULL
          AND s.status = 'active'
        )
        OR (
          p_session_id IS NULL
          AND p_archive_date IS NOT NULL
          AND coalesce(s.archive_date, (s.started_at AT TIME ZONE 'Europe/Oslo')::date) = p_archive_date
        )
      )
    ORDER BY ev.recorded_at
    LIMIT 4000
  ) x;

  RETURN jsonb_build_object(
    'sessions', v_sessions,
    'samples', v_samples,
    'events', v_events
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_drive_monitor_map_payload(UUID, UUID, DATE) TO authenticated;
