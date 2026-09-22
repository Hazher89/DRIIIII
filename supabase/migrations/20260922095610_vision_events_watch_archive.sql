-- Watch / archive metadata for sorting (and other) vision clips.

alter table public.vision_events
  add column if not exists viewed_at timestamptz,
  add column if not exists viewed_by uuid references auth.users (id) on delete set null,
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references auth.users (id) on delete set null;

create index if not exists vision_events_company_active_idx
  on public.vision_events (company_id, occurred_at desc)
  where archived_at is null and status <> 'dismissed';

comment on column public.vision_events.viewed_at is
  'Når klippet sist ble åpnet i DriftPro.';
comment on column public.vision_events.archived_at is
  'Arkivert — skjules fra hovedfeed, synlig under Arkiv.';

create or replace function public.mark_vision_event_viewed(p_event_id uuid)
returns public.vision_events
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.vision_events%rowtype;
  v_company uuid;
begin
  select company_id into v_company from public.profiles where id = auth.uid();
  if v_company is null then
    raise exception 'Ingen bedrift';
  end if;

  update public.vision_events e
  set
    viewed_at = now(),
    viewed_by = auth.uid()
  where e.id = p_event_id
    and e.company_id = v_company
  returning * into v_row;

  if not found then
    raise exception 'Hendelse ikke funnet';
  end if;
  return v_row;
end;
$$;

create or replace function public.set_vision_event_archived(
  p_event_id uuid,
  p_archived boolean default true
)
returns public.vision_events
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.vision_events%rowtype;
  v_company uuid;
  v_role text;
begin
  select company_id, role::text into v_company, v_role
  from public.profiles where id = auth.uid();
  if v_company is null then
    raise exception 'Ingen bedrift';
  end if;

  update public.vision_events e
  set
    archived_at = case when p_archived then now() else null end,
    archived_by = case when p_archived then auth.uid() else null end
  where e.id = p_event_id
    and e.company_id = v_company
  returning * into v_row;

  if not found then
    raise exception 'Hendelse ikke funnet';
  end if;
  return v_row;
end;
$$;

create or replace function public.soft_delete_vision_event(p_event_id uuid)
returns public.vision_events
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.vision_events%rowtype;
  v_company uuid;
begin
  select company_id into v_company from public.profiles where id = auth.uid();
  if v_company is null then
    raise exception 'Ingen bedrift';
  end if;

  update public.vision_events e
  set
    status = 'dismissed',
    archived_at = coalesce(e.archived_at, now()),
    archived_by = coalesce(e.archived_by, auth.uid())
  where e.id = p_event_id
    and e.company_id = v_company
  returning * into v_row;

  if not found then
    raise exception 'Hendelse ikke funnet';
  end if;
  return v_row;
end;
$$;

grant execute on function public.mark_vision_event_viewed(uuid) to authenticated;
grant execute on function public.set_vision_event_archived(uuid, boolean) to authenticated;
grant execute on function public.soft_delete_vision_event(uuid) to authenticated;
