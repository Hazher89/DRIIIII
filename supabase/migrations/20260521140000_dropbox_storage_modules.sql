-- Per-modul valg for Dropbox-lagring (store filer).

alter table public.company_dropbox_connections
  add column if not exists storage_modules jsonb not null default '{
    "routes": true,
    "tickets": true,
    "dms": true,
    "partners": true,
    "employees": true,
    "hms": true
  }'::jsonb;

comment on column public.company_dropbox_connections.storage_modules is
  'Hvilke DriftPro-moduler som bruker Dropbox for filer over threshold.';

create or replace function public.set_company_dropbox_storage_modules(p_modules jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_role text;
  merged jsonb;
begin
  select company_id, role::text into v_company, v_role
  from public.profiles where id = auth.uid();

  if v_company is null then
    raise exception 'Ingen bedrift';
  end if;
  if v_role is null or v_role not in ('admin', 'superadmin') then
    raise exception 'Kun administrator';
  end if;

  if not exists (select 1 from public.company_dropbox_connections where company_id = v_company) then
    raise exception 'Dropbox er ikke koblet';
  end if;

  merged := coalesce(
    (select storage_modules from public.company_dropbox_connections where company_id = v_company),
    '{}'::jsonb
  ) || coalesce(p_modules, '{}'::jsonb);

  update public.company_dropbox_connections
  set storage_modules = merged, updated_at = now()
  where company_id = v_company;

  return merged;
end;
$$;

revoke all on function public.set_company_dropbox_storage_modules(jsonb) from public;
grant execute on function public.set_company_dropbox_storage_modules(jsonb) to authenticated;

-- Utvid status-RPC
create or replace function public.get_company_dropbox_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_role text;
  row public.company_dropbox_connections%rowtype;
begin
  select company_id, role::text into v_company, v_role
  from public.profiles where id = auth.uid();

  if v_company is null then
    raise exception 'Ingen bedrift';
  end if;
  if v_role is null or v_role not in ('admin', 'superadmin') then
    raise exception 'Kun administrator';
  end if;

  select * into row from public.company_dropbox_connections where company_id = v_company;

  if not found then
    return jsonb_build_object('connected', false);
  end if;

  return jsonb_build_object(
    'connected', true,
    'account_email', row.account_email,
    'root_folder', row.root_folder,
    'large_file_threshold_bytes', row.large_file_threshold_bytes,
    'connected_at', row.connected_at,
    'storage_modules', coalesce(row.storage_modules, '{}'::jsonb)
  );
end;
$$;
