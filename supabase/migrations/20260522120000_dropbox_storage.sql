-- Dropbox som ekstern fillagring (metadata i Postgres, filer i Dropbox /DriftPro/...).
-- refresh_token leses KUN av edge functions (service role), aldri av klient.

create table if not exists public.company_dropbox_connections (
  company_id uuid primary key references public.companies(id) on delete cascade,
  dropbox_account_id text,
  account_email text,
  root_folder text not null default '/DriftPro',
  refresh_token text not null,
  access_token text,
  token_expires_at timestamptz,
  large_file_threshold_bytes int not null default 1048576,
  connected_at timestamptz not null default now(),
  connected_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

comment on table public.company_dropbox_connections is
  'OAuth-tilkobling til Dropbox per bedrift. Filer over threshold lagres i Dropbox.';

alter table public.company_dropbox_connections enable row level security;

-- Kun metadata for admin (ikke refresh_token).
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
    'connected_at', row.connected_at
  );
end;
$$;

revoke all on function public.get_company_dropbox_status() from public;
grant execute on function public.get_company_dropbox_status() to authenticated;

create or replace function public.disconnect_company_dropbox()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_role text;
begin
  select company_id, role::text into v_company, v_role
  from public.profiles where id = auth.uid();

  if v_role is null or v_role not in ('admin', 'superadmin') then
    raise exception 'Kun administrator';
  end if;

  delete from public.company_dropbox_connections where company_id = v_company;
end;
$$;

revoke all on function public.disconnect_company_dropbox() from public;
grant execute on function public.disconnect_company_dropbox() to authenticated;

-- Valgfri: spor hvor filen ligger
alter table public.dms_files
  add column if not exists storage_provider text not null default 'supabase',
  add column if not exists external_url text,
  add column if not exists file_size_bytes bigint;

alter table public.partner_route_shares
  add column if not exists storage_provider text not null default 'supabase',
  add column if not exists external_url text;
