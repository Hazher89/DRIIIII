-- Live-kart: vis aktive + alle sesjoner fra i dag (Oslo).
-- Gjør arkiv/live mer robust når sesjon er avsluttet samme dag.

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
  v_today DATE := (now() AT TIME ZONE 'Europe/Oslo')::date;
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
        AND (
          s.status = 'active'
          OR coalesce(
               s.archive_date,
               (s.started_at AT TIME ZONE 'Europe/Oslo')::date
             ) = v_today
        )
      )
      OR (
        p_session_id IS NULL
        AND p_archive_date IS NOT NULL
        AND coalesce(
              s.archive_date,
              (s.started_at AT TIME ZONE 'Europe/Oslo')::date
            ) = p_archive_date
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
          AND (
            s.status = 'active'
            OR coalesce(
                 s.archive_date,
                 (s.started_at AT TIME ZONE 'Europe/Oslo')::date
               ) = v_today
          )
        )
        OR (
          p_session_id IS NULL
          AND p_archive_date IS NOT NULL
          AND coalesce(
                s.archive_date,
                (s.started_at AT TIME ZONE 'Europe/Oslo')::date
              ) = p_archive_date
        )
      )
    ORDER BY sm.recorded_at
    LIMIT 12000
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
          AND (
            s.status = 'active'
            OR coalesce(
                 s.archive_date,
                 (s.started_at AT TIME ZONE 'Europe/Oslo')::date
               ) = v_today
          )
        )
        OR (
          p_session_id IS NULL
          AND p_archive_date IS NOT NULL
          AND coalesce(
                s.archive_date,
                (s.started_at AT TIME ZONE 'Europe/Oslo')::date
              ) = p_archive_date
        )
      )
    ORDER BY ev.recorded_at
    LIMIT 6000
  ) x;

  RETURN jsonb_build_object(
    'sessions', v_sessions,
    'samples', v_samples,
    'events', v_events,
    'today', v_today::text
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_drive_monitor_map_payload(UUID, UUID, DATE) TO authenticated;
