-- Feedback fra avviksvideo («Dette var riktig») uten aktiv lære-session.
-- Tillat session_id = null; knytt valgfritt til vision_events.

alter table public.vision_learn_labels
  alter column session_id drop not null;

alter table public.vision_learn_labels
  add column if not exists event_id uuid references public.vision_events (id) on delete set null;

create index if not exists vision_learn_labels_event_idx
  on public.vision_learn_labels (event_id)
  where event_id is not null;

comment on column public.vision_learn_labels.event_id is
  'Valgfri kobling til sorterings-avvik når bruker merker Riktig/Feil uten lære-session.';

create or replace function public.mark_vision_sorting_feedback(
  p_event_id uuid,
  p_label text default 'correct'
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

  -- Finn vision_cameras-rad (uuid) for bedriften / sorting.
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
    'event:' || p_event_id::text,
    auth.uid()
  );

  -- Arkiver + merk sett når bruker sier «dette var riktig».
  update public.vision_events e
  set
    viewed_at = coalesce(e.viewed_at, now()),
    archived_at = case
      when p_label = 'correct' then coalesce(e.archived_at, now())
      else e.archived_at
    end,
    status = case
      when p_label = 'correct' then 'resolved'
      else e.status
    end
  where e.id = p_event_id
  returning * into v_event;

  return v_event;
end;
$$;

grant execute on function public.mark_vision_sorting_feedback(uuid, text) to authenticated;
