-- Bulk-resolve false sorting alarms (temporary cardboard dump in B).
-- Marking one as «ikke avvik» clears all unlabeled of the same reason.

CREATE OR REPLACE FUNCTION public.bulk_resolve_sorting_reason(
  p_reason text,
  p_note text DEFAULT 'Auto: midlertidig tømming i B → flyttes til A er OK'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_company uuid;
  n_updated int := 0;
  n_labels int := 0;
  v_cam uuid;
  v_uid uuid := auth.uid();
  rec RECORD;
  v_note text;
BEGIN
  v_role := public.get_user_role()::text;
  SELECT company_id INTO v_company FROM public.profiles WHERE id = v_uid;

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  IF v_role NOT IN ('admin', 'superadmin', 'leder') THEN
    RAISE EXCEPTION 'Mangler tilgang';
  END IF;

  -- Sorteringsklipp ligger på MAVI (nil UUID).
  IF v_role = 'superadmin' OR v_company = '00000000-0000-0000-0000-000000000000'::uuid THEN
    v_company := '00000000-0000-0000-0000-000000000000'::uuid;
  ELSIF v_company IS NULL THEN
    RAISE EXCEPTION 'Ingen bedrift';
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) < 2 THEN
    RAISE EXCEPTION 'Ugyldig reason';
  END IF;

  v_note := coalesce(nullif(trim(p_note), ''), 'Bulk: ikke avvik');

  SELECT c.id INTO v_cam
  FROM public.vision_cameras c
  WHERE c.company_id = v_company
    AND c.event_type = 'sorting_clip'
  ORDER BY CASE WHEN c.enabled THEN 0 ELSE 1 END, c.created_at DESC NULLS LAST
  LIMIT 1;

  IF v_cam IS NULL THEN
    SELECT c.id INTO v_cam
    FROM public.vision_cameras c
    WHERE c.event_type = 'sorting_clip'
    ORDER BY CASE WHEN c.company_id = v_company THEN 0 ELSE 1 END,
             CASE WHEN c.enabled THEN 0 ELSE 1 END
    LIMIT 1;
  END IF;

  FOR rec IN
    SELECT id, metadata, company_id
    FROM public.vision_events
    WHERE company_id = v_company
      AND event_type = 'sorting_clip'
      AND status <> 'dismissed'
      AND coalesce(metadata->>'reason', '') = p_reason
      AND coalesce(metadata->>'human_label', '') = ''
  LOOP
    UPDATE public.vision_events
    SET
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'human_label', 'correct',
        'human_note', v_note,
        'needs_review', false,
        'bulk_resolved_at', now()::text,
        'reviewed_at', now()::text
      ),
      archived_at = coalesce(archived_at, now()),
      archived_by = coalesce(archived_by, v_uid),
      viewed_at = coalesce(viewed_at, now()),
      viewed_by = coalesce(viewed_by, v_uid),
      status = 'resolved',
      updated_at = now()
    WHERE id = rec.id;
    n_updated := n_updated + 1;

    IF v_cam IS NOT NULL THEN
      DELETE FROM public.vision_learn_labels
      WHERE event_id = rec.id AND created_by = v_uid;

      INSERT INTO public.vision_learn_labels (
        company_id, session_id, camera_id, event_id, label, zone, reason, note, created_by
      ) VALUES (
        rec.company_id,
        NULL,
        v_cam,
        rec.id,
        'correct',
        nullif(rec.metadata->>'zone', ''),
        p_reason,
        v_note,
        v_uid
      );
      n_labels := n_labels + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'reason', p_reason,
    'updated', n_updated,
    'learn_labels', n_labels
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.bulk_resolve_sorting_reason(text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_vision_sorting_feedback(
  p_event_id uuid,
  p_label text DEFAULT 'correct',
  p_note text DEFAULT NULL
)
RETURNS public.vision_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company uuid;
  v_event public.vision_events%rowtype;
  v_cam_uuid uuid;
  v_zone text;
  v_reason text;
  v_note text;
  v_role text;
BEGIN
  v_role := public.get_user_role()::text;
  SELECT company_id INTO v_company FROM public.profiles WHERE id = auth.uid();
  IF v_company IS NULL AND v_role <> 'superadmin' THEN
    RAISE EXCEPTION 'Ingen bedrift';
  END IF;

  IF p_label NOT IN ('correct', 'wrong') THEN
    RAISE EXCEPTION 'label må være correct eller wrong';
  END IF;

  SELECT * INTO v_event
  FROM public.vision_events
  WHERE id = p_event_id
    AND status <> 'dismissed'
    AND (
      company_id = v_company
      OR v_role = 'superadmin'
      OR company_id = '00000000-0000-0000-0000-000000000000'::uuid
    );
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Hendelse ikke funnet';
  END IF;

  v_zone := nullif(trim(v_event.metadata->>'zone'), '');
  v_reason := nullif(trim(v_event.metadata->>'reason'), '');
  v_note := nullif(trim(coalesce(p_note, '')), '');

  SELECT c.id INTO v_cam_uuid
  FROM public.vision_cameras c
  WHERE c.company_id = v_event.company_id
    AND c.event_type = 'sorting_clip'
  ORDER BY
    CASE WHEN c.enabled THEN 0 ELSE 1 END,
    CASE WHEN c.name = v_event.camera_id THEN 0 ELSE 1 END,
    c.created_at DESC NULLS LAST
  LIMIT 1;

  IF v_cam_uuid IS NULL THEN
    SELECT c.id INTO v_cam_uuid
    FROM public.vision_cameras c
    WHERE c.event_type = 'sorting_clip'
    ORDER BY
      CASE WHEN c.company_id = v_event.company_id THEN 0 ELSE 1 END,
      CASE WHEN c.enabled THEN 0 ELSE 1 END,
      c.created_at DESC NULLS LAST
    LIMIT 1;
  END IF;

  IF v_cam_uuid IS NULL THEN
    RAISE EXCEPTION 'Ingen vision-kamera funnet for bedriften';
  END IF;

  DELETE FROM public.vision_learn_labels
  WHERE event_id = p_event_id AND created_by = auth.uid();

  INSERT INTO public.vision_learn_labels (
    company_id, session_id, camera_id, event_id, label, zone, reason, note, created_by
  ) VALUES (
    v_event.company_id,
    NULL,
    v_cam_uuid,
    p_event_id,
    p_label,
    v_zone,
    coalesce(v_reason, 'sorting_feedback'),
    coalesce(v_note, 'event:' || p_event_id::text),
    auth.uid()
  );

  UPDATE public.vision_events e
  SET
    viewed_at = coalesce(e.viewed_at, now()),
    viewed_by = coalesce(e.viewed_by, auth.uid()),
    archived_at = CASE
      WHEN p_label = 'correct' THEN coalesce(e.archived_at, now())
      ELSE NULL
    END,
    archived_by = CASE
      WHEN p_label = 'correct' THEN coalesce(e.archived_by, auth.uid())
      ELSE NULL
    END,
    status = CASE
      WHEN p_label = 'correct' THEN 'resolved'
      WHEN p_label = 'wrong' THEN 'acknowledged'
      ELSE e.status
    END,
    metadata = coalesce(e.metadata, '{}'::jsonb) || jsonb_build_object(
      'human_label', p_label,
      'human_note', to_jsonb(v_note),
      'needs_review', false,
      'reviewed_at', to_jsonb(now()),
      'reviewed_by', to_jsonb(auth.uid()::text)
    )
  WHERE e.id = p_event_id
  RETURNING * INTO v_event;

  -- Én «ikke avvik» på B-midlertidig / ubrettet-FP → rydd hele køen.
  IF p_label = 'correct' AND v_reason IN (
    'cardboard_in_wrong_bin',
    'person_visit',
    'unflattened_cardboard'
  ) THEN
    BEGIN
      PERFORM public.bulk_resolve_sorting_reason(
        v_reason,
        coalesce(v_note, 'Lært: ikke avvik — samme årsak ryddet')
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'bulk_resolve_sorting_reason failed: %', SQLERRM;
    END;
  END IF;

  RETURN v_event;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_vision_sorting_feedback(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_vision_sorting_feedback(uuid, text) TO authenticated;
