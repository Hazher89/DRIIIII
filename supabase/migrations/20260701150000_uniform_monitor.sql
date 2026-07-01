-- Uniform-monitor: utvider vision_events og vision_cameras + tilgangskontroll.

alter table public.vision_events
  drop constraint if exists vision_events_event_type_check;

alter table public.vision_events
  add constraint vision_events_event_type_check
  check (event_type in (
    'ppe_violation',
    'uniform_violation',
    'parking_entry',
    'parking_exit'
  ));

alter table public.vision_cameras
  drop constraint if exists vision_cameras_event_type_check;

alter table public.vision_cameras
  add constraint vision_cameras_event_type_check
  check (event_type in (
    'ppe_violation',
    'uniform_violation',
    'parking_entry',
    'parking_exit'
  ));

alter table public.vision_cameras
  alter column event_type set default 'uniform_violation';

comment on column public.vision_events.metadata is
  'JSON: track_id, confidence, bbox, missing_logo, missing_shoes, logo_score, shoes_score';

-- Hjelper: har bruker uniform-monitor-tilgang?
create or replace function public.profile_has_uniform_monitor()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and (
        p.role::text = 'superadmin'
        or coalesce(p.access_settings->>'uniform_monitor', 'false') = 'true'
      )
  );
$$;

grant execute on function public.profile_has_uniform_monitor() to authenticated;

create or replace function public.profile_has_uniform_monitor_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and (
        p.role::text = 'superadmin'
        or coalesce(p.access_settings->>'uniform_monitor_admin', 'false') = 'true'
        or p.role::text in ('admin', 'leder')
      )
  );
$$;

grant execute on function public.profile_has_uniform_monitor_admin() to authenticated;

-- Begrens lesing av hendelser til de med uniform-monitor.
drop policy if exists vision_events_select_company on public.vision_events;

drop policy if exists vision_events_select_uniform on public.vision_events;

create policy vision_events_select_uniform
  on public.vision_events
  for select
  to authenticated
  using (
    company_id = (select company_id from public.profiles where id = auth.uid())
    and public.profile_has_uniform_monitor()
  );

drop policy if exists vision_cameras_admin_write on public.vision_cameras;

create policy vision_cameras_admin_write
  on public.vision_cameras for all to authenticated
  using (
    company_id = (select company_id from public.profiles where id = auth.uid())
    and public.profile_has_uniform_monitor_admin()
  )
  with check (
    company_id = (select company_id from public.profiles where id = auth.uid())
    and public.profile_has_uniform_monitor_admin()
  );

-- Worker henter kamera med passord (kun service role).
create or replace function public.get_vision_camera_for_worker(p_camera_id uuid)
returns public.vision_cameras
language sql
security definer
set search_path = public
as $$
  select *
  from public.vision_cameras
  where id = p_camera_id and enabled = true
  limit 1;
$$;

revoke all on function public.get_vision_camera_for_worker(uuid) from public;
grant execute on function public.get_vision_camera_for_worker(uuid) to service_role;
