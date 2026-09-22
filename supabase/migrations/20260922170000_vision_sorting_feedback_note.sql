-- Riktig/Feil med kommentar på alle sorteringsbesøk; lagre human_label i metadata.

create or replace function public.mark_vision_sorting_feedback(
  p_event_id uuid,
  p_label text default 'correct',
  p_note text default null
)
returns public.vision_events
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_event public.vision_events%rowtype;
  v_cam_uuid uuid;
  v_zone text;
  v_reason text;
  v_note text;
begin
  select company_id into v_company from public.profiles where id = auth.uid();
  if v_company is null then raise exception 'Ingen bedrift'; end if;

  if p_label not in ('correct', 'wrong') then
    raise exception 'label må være correct eller wrong';
  end if;

  select * into v_event
  from public.vision_events
  where id = p_event_id
    and company_id = v_company
    and status <> 'dismissed';
  if not found then raise exception 'Hendelse ikke funnet'; end if;

  v_zone := nullif(trim(v_event.metadata->>'zone'), '');
  v_reason := nullif(trim(v_event.metadata->>'reason'), '');
  v_note := nullif(trim(coalesce(p_note, '')), '');

  select c.id into v_cam_uuid
  from public.vision_cameras c
  where c.company_id = v_company
    and c.event_type = 'sorting_clip'
  order by
    case when c.enabled then 0 else 1 end,
    case when c.name = v_event.camera_id then 0 else 1 end,
    c.created_at desc nulls last
  limit 1;

  if v_cam_uuid is null then
    select c.id into v_cam_uuid
    from public.vision_cameras c
    where c.event_type = 'sorting_clip'
    order by
      case when c.company_id = v_company then 0 else 1 end,
      case when c.enabled then 0 else 1 end,
      c.created_at desc nulls last
    limit 1;
  end if;

  if v_cam_uuid is null then
    select c.id into v_cam_uuid
    from public.vision_cameras c
    where c.company_id = v_company
    order by c.created_at desc nulls last
    limit 1;
  end if;

  if v_cam_uuid is null then
    raise exception 'Ingen vision-kamera funnet for bedriften';
  end if;

  -- Unngå doble labels på samme event (oppdater via slett+insert er tungt — skip hvis finnes).
  delete from public.vision_learn_labels
  where event_id = p_event_id and created_by = auth.uid();

  insert into public.vision_learn_labels (
    company_id, session_id, camera_id, event_id, label, zone, reason, note, created_by
  ) values (
    v_company,
    null,
    v_cam_uuid,
    p_event_id,
    p_label,
    v_zone,
    coalesce(v_reason, 'sorting_feedback'),
    coalesce(
      v_note,
      'event:' || p_event_id::text
    ),
    auth.uid()
  );

  update public.vision_events e
  set
    viewed_at = coalesce(e.viewed_at, now()),
    viewed_by = coalesce(e.viewed_by, auth.uid()),
    archived_at = case
      when p_label = 'correct' then coalesce(e.archived_at, now())
      else null
    end,
    archived_by = case
      when p_label = 'correct' then coalesce(e.archived_by, auth.uid())
      else null
    end,
    status = case
      when p_label = 'correct' then 'resolved'
      when p_label = 'wrong' then 'acknowledged'
      else e.status
    end,
    metadata = coalesce(e.metadata, '{}'::jsonb) || jsonb_build_object(
      'human_label', p_label,
      'human_note', to_jsonb(v_note),
      'needs_review', false,
      'reviewed_at', to_jsonb(now()),
      'reviewed_by', to_jsonb(auth.uid()::text)
    )
  where e.id = p_event_id
  returning * into v_event;

  return v_event;
end;
$$;

-- Ny signatur med kommentar (behold 2-arg via default).
grant execute on function public.mark_vision_sorting_feedback(uuid, text, text) to authenticated;
-- Drop old 2-arg overload if present as separate; Postgres treats default as one function.
grant execute on function public.mark_vision_sorting_feedback(uuid, text) to authenticated;
