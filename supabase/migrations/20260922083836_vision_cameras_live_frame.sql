-- Nesten-live bilde fra edge-worker (Dropbox overwrite + metadata for DriftPro).

alter table public.vision_cameras
  add column if not exists live_dropbox_path text,
  add column if not exists live_image_url text,
  add column if not exists live_updated_at timestamptz,
  add column if not exists zone_a_name text not null default 'Container A (papp)',
  add column if not exists zone_b_name text not null default 'Container B (annet)';

comment on column public.vision_cameras.live_dropbox_path is
  'Fast Dropbox-sti for siste live-JPEG (overskrives av worker).';
comment on column public.vision_cameras.live_image_url is
  'Siste midlertidige Dropbox-lenke (kan utløpe; edge henter ny ved behov).';
comment on column public.vision_cameras.zone_a_name is
  'Venstre sone / komprimator A — visningsnavn i DriftPro.';
comment on column public.vision_cameras.zone_b_name is
  'Høyre sone / komprimator B — visningsnavn i DriftPro.';

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
    'created_at', c.created_at,
    'updated_at', c.updated_at
  )
  from public.vision_cameras c
  where c.company_id = v_company
  order by c.name;
end;
$$;

grant execute on function public.list_vision_cameras_masked() to authenticated;
