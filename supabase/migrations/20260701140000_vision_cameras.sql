-- Kameraer for vision monitor (PPE / parkering) — admin styrt, flere per bedrift.

create table if not exists public.vision_cameras (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  host text not null,
  http_port int not null default 80 check (http_port > 0 and http_port < 65536),
  camera_user text not null default 'admin',
  camera_password text not null default '',
  snapshot_path text not null default '/ISAPI/Streaming/channels/101/picture',
  event_type text not null default 'ppe_violation' check (
    event_type in ('ppe_violation', 'parking_entry', 'parking_exit')
  ),
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists vision_cameras_company_idx
  on public.vision_cameras (company_id, enabled, name);

comment on table public.vision_cameras is
  'IP-kameraer for vision monitor. Passord kun for admin og edge-worker.';

alter table public.vision_cameras enable row level security;

drop policy if exists vision_cameras_select_company on public.vision_cameras;
drop policy if exists vision_cameras_admin_write on public.vision_cameras;

create policy vision_cameras_select_company
  on public.vision_cameras for select to authenticated
  using (
    company_id = (select company_id from public.profiles where id = auth.uid())
  );

create policy vision_cameras_admin_write
  on public.vision_cameras for all to authenticated
  using (
    company_id = (select company_id from public.profiles where id = auth.uid())
    and (select role::text from public.profiles where id = auth.uid())
      in ('admin', 'superadmin', 'leder')
  )
  with check (
    company_id = (select company_id from public.profiles where id = auth.uid())
    and (select role::text from public.profiles where id = auth.uid())
      in ('admin', 'superadmin', 'leder')
  );

grant select, insert, update, delete on public.vision_cameras to authenticated;
grant all on public.vision_cameras to service_role;

-- Masker passord i liste (admin ser at det finnes, ikke klartekst i JSON til klient ved behov).
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
    'created_at', c.created_at,
    'updated_at', c.updated_at
  )
  from public.vision_cameras c
  where c.company_id = v_company
  order by c.name;
end;
$$;

grant execute on function public.list_vision_cameras_masked() to authenticated;

-- Edge worker (service role): alle aktive kameraer med passord.
create or replace function public.list_vision_cameras_for_worker(p_company_id uuid default null)
returns setof public.vision_cameras
language sql
security definer
set search_path = public
as $$
  select *
  from public.vision_cameras
  where enabled = true
    and (p_company_id is null or company_id = p_company_id)
  order by company_id, name;
$$;

revoke all on function public.list_vision_cameras_for_worker(uuid) from public;
grant execute on function public.list_vision_cameras_for_worker(uuid) to service_role;
