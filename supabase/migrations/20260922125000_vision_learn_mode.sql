-- Læremodus for sorteringskamera: kontinuerlig opptak + merking i DriftPro.

alter table public.vision_cameras
  add column if not exists learn_mode boolean not null default false,
  add column if not exists learn_session_id uuid,
  add column if not exists learn_started_at timestamptz,
  add column if not exists learn_started_by uuid references auth.users (id) on delete set null;

comment on column public.vision_cameras.learn_mode is
  'Når true tar Windows-worker opp kontinuerlig til session stoppes.';
comment on column public.vision_cameras.learn_session_id is
  'Aktiv vision_learn_sessions.id mens learn_mode er på.';

create table if not exists public.vision_learn_sessions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  camera_id uuid not null references public.vision_cameras (id) on delete cascade,
  status text not null default 'recording'
    check (status in ('recording', 'uploading', 'ready', 'failed', 'cancelled')),
  started_at timestamptz not null default now(),
  started_by uuid references auth.users (id) on delete set null,
  stopped_at timestamptz,
  stopped_by uuid references auth.users (id) on delete set null,
  dropbox_video_path text,
  dropbox_video_url text,
  dropbox_paths jsonb not null default '[]'::jsonb,
  duration_seconds numeric,
  chunk_count int not null default 0,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists vision_learn_sessions_company_idx
  on public.vision_learn_sessions (company_id, started_at desc);
create index if not exists vision_learn_sessions_camera_idx
  on public.vision_learn_sessions (camera_id, started_at desc);

comment on table public.vision_learn_sessions is
  'Læremodus-opptak fra Windows-worker (chunked MP4).';

create table if not exists public.vision_learn_labels (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  session_id uuid not null references public.vision_learn_sessions (id) on delete cascade,
  camera_id uuid not null references public.vision_cameras (id) on delete cascade,
  label text not null check (label in ('correct', 'wrong')),
  zone text,
  reason text,
  note text,
  timestamp_in_video_sec numeric,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists vision_learn_labels_session_idx
  on public.vision_learn_labels (session_id, created_at desc);
create index if not exists vision_learn_labels_company_idx
  on public.vision_learn_labels (company_id, created_at desc);

comment on table public.vision_learn_labels is
  'Riktig/feil-merking på læremodus-video (treningsdata v1).';

alter table public.vision_learn_sessions enable row level security;
alter table public.vision_learn_labels enable row level security;

drop policy if exists vision_learn_sessions_select on public.vision_learn_sessions;
create policy vision_learn_sessions_select
  on public.vision_learn_sessions for select to authenticated
  using (
    company_id = (select company_id from public.profiles where id = auth.uid())
  );

drop policy if exists vision_learn_sessions_admin_write on public.vision_learn_sessions;
create policy vision_learn_sessions_admin_write
  on public.vision_learn_sessions for all to authenticated
  using (
    company_id = (select company_id from public.profiles where id = auth.uid())
    and (select role::text from public.profiles where id = auth.uid())
      in ('admin', 'superadmin', 'leder', 'owner')
  )
  with check (
    company_id = (select company_id from public.profiles where id = auth.uid())
  );

drop policy if exists vision_learn_labels_select on public.vision_learn_labels;
create policy vision_learn_labels_select
  on public.vision_learn_labels for select to authenticated
  using (
    company_id = (select company_id from public.profiles where id = auth.uid())
  );

drop policy if exists vision_learn_labels_insert on public.vision_learn_labels;
create policy vision_learn_labels_insert
  on public.vision_learn_labels for insert to authenticated
  with check (
    company_id = (select company_id from public.profiles where id = auth.uid())
  );

grant select, insert, update on public.vision_learn_sessions to authenticated;
grant select, insert on public.vision_learn_labels to authenticated;
grant all on public.vision_learn_sessions to service_role;
grant all on public.vision_learn_labels to service_role;

-- Oppdater masked camera list med learn-felter.
create or replace function public.list_vision_cameras_masked()
returns setof jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
begin
  select company_id into v_company from public.profiles where id = auth.uid();
  if v_company is null then raise exception 'Ingen bedrift'; end if;

  return query
  select jsonb_build_object(
    'id', c.id,
    'company_id', c.company_id,
    'name', c.name,
    'host', c.host,
    'http_port', c.http_port,
    'camera_user', c.camera_user,
    'has_password', (c.camera_password is not null and length(c.camera_password) > 0),
    'snapshot_path', c.snapshot_path,
    'event_type', c.event_type,
    'enabled', c.enabled,
    'live_image_url', c.live_image_url,
    'live_updated_at', c.live_updated_at,
    'zone_a_name', c.zone_a_name,
    'zone_b_name', c.zone_b_name,
    'learn_mode', c.learn_mode,
    'learn_session_id', c.learn_session_id,
    'learn_started_at', c.learn_started_at,
    'created_at', c.created_at,
    'updated_at', c.updated_at
  )
  from public.vision_cameras c
  where c.company_id = v_company
  order by c.name;
end;
$$;

grant execute on function public.list_vision_cameras_masked() to authenticated;

-- Start læremodus: opprett session + sett flagg på kamera.
create or replace function public.start_vision_learn_mode(p_camera_id uuid)
returns public.vision_learn_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_cam public.vision_cameras%rowtype;
  v_session public.vision_learn_sessions%rowtype;
begin
  select company_id into v_company from public.profiles where id = auth.uid();
  if v_company is null then raise exception 'Ingen bedrift'; end if;

  select * into v_cam from public.vision_cameras
  where id = p_camera_id and company_id = v_company;
  if not found then raise exception 'Kamera ikke funnet'; end if;

  if v_cam.learn_mode and v_cam.learn_session_id is not null then
    select * into v_session from public.vision_learn_sessions
    where id = v_cam.learn_session_id;
    if found then return v_session; end if;
  end if;

  insert into public.vision_learn_sessions (
    company_id, camera_id, status, started_by
  ) values (
    v_company, p_camera_id, 'recording', auth.uid()
  )
  returning * into v_session;

  update public.vision_cameras
  set
    learn_mode = true,
    learn_session_id = v_session.id,
    learn_started_at = now(),
    learn_started_by = auth.uid(),
    updated_at = now()
  where id = p_camera_id;

  return v_session;
end;
$$;

-- Stopp læremodus: worker finaliserer video; app kan kalle dette først.
create or replace function public.stop_vision_learn_mode(p_camera_id uuid)
returns public.vision_learn_sessions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_cam public.vision_cameras%rowtype;
  v_session public.vision_learn_sessions%rowtype;
begin
  select company_id into v_company from public.profiles where id = auth.uid();
  if v_company is null then raise exception 'Ingen bedrift'; end if;

  select * into v_cam from public.vision_cameras
  where id = p_camera_id and company_id = v_company;
  if not found then raise exception 'Kamera ikke funnet'; end if;

  update public.vision_cameras
  set
    learn_mode = false,
    updated_at = now()
  where id = p_camera_id;

  if v_cam.learn_session_id is null then
    raise exception 'Ingen aktiv lære-session';
  end if;

  update public.vision_learn_sessions
  set
    status = case when status = 'recording' then 'uploading' else status end,
    stopped_at = coalesce(stopped_at, now()),
    stopped_by = coalesce(stopped_by, auth.uid()),
    updated_at = now()
  where id = v_cam.learn_session_id
  returning * into v_session;

  if not found then raise exception 'Session ikke funnet'; end if;
  return v_session;
end;
$$;

create or replace function public.add_vision_learn_label(
  p_session_id uuid,
  p_label text,
  p_zone text default null,
  p_reason text default null,
  p_note text default null,
  p_timestamp_in_video_sec numeric default null
)
returns public.vision_learn_labels
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_session public.vision_learn_sessions%rowtype;
  v_row public.vision_learn_labels%rowtype;
begin
  select company_id into v_company from public.profiles where id = auth.uid();
  if v_company is null then raise exception 'Ingen bedrift'; end if;

  if p_label not in ('correct', 'wrong') then
    raise exception 'label må være correct eller wrong';
  end if;

  select * into v_session from public.vision_learn_sessions
  where id = p_session_id and company_id = v_company;
  if not found then raise exception 'Session ikke funnet'; end if;

  insert into public.vision_learn_labels (
    company_id, session_id, camera_id, label, zone, reason, note,
    timestamp_in_video_sec, created_by
  ) values (
    v_company, p_session_id, v_session.camera_id, p_label, p_zone, p_reason,
    p_note, p_timestamp_in_video_sec, auth.uid()
  )
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.start_vision_learn_mode(uuid) to authenticated;
grant execute on function public.stop_vision_learn_mode(uuid) to authenticated;
grant execute on function public.add_vision_learn_label(uuid, text, text, text, text, numeric) to authenticated;
