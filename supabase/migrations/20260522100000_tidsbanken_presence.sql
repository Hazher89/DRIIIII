-- Live nærvær fra Tidsbanken (synkronisert ca. hvert 3. min via edge function).

create table if not exists public.tidsbanken_presence (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_number text not null,
  first_name text not null default '',
  last_name text not null default '',
  status text not null default 'ingen',
  status_label text not null default '',
  department_code text,
  since_time text,
  planned_from text,
  planned_to text,
  raw jsonb,
  synced_at timestamptz not null default now(),
  unique (company_id, employee_number)
);

create index if not exists idx_tidsbanken_presence_company_status
  on public.tidsbanken_presence (company_id, status);

create table if not exists public.tidsbanken_sync_state (
  company_id uuid primary key references public.companies(id) on delete cascade,
  last_sync_at timestamptz,
  clocked_in_count int not null default 0,
  total_count int not null default 0,
  last_error text,
  updated_at timestamptz not null default now()
);

alter table public.companies
  add column if not exists tidsbanken_enabled boolean not null default false;

comment on table public.tidsbanken_presence is
  'Siste kjente stemplestatus per ansatt (fra Tidsbanken API).';
comment on column public.companies.tidsbanken_enabled is
  'Når true kjører tidsbanken-sync (TIDSBANKEN_FIRMA_* og TIDSBANKEN_ANSATT_* i Supabase Secrets).';

alter table public.tidsbanken_presence enable row level security;
alter table public.tidsbanken_sync_state enable row level security;

drop policy if exists tidsbanken_presence_select_company on public.tidsbanken_presence;
create policy tidsbanken_presence_select_company on public.tidsbanken_presence
  for select to authenticated
  using (
    company_id in (
      select p.company_id from public.profiles p where p.id = auth.uid()
    )
  );

drop policy if exists tidsbanken_sync_state_select_company on public.tidsbanken_sync_state;
create policy tidsbanken_sync_state_select_company on public.tidsbanken_sync_state
  for select to authenticated
  using (
    company_id in (
      select p.company_id from public.profiles p where p.id = auth.uid()
    )
  );

-- Utvid standard infoskjerm-innstillinger.
create or replace function public.default_kiosk_settings()
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'infoscreen_layout_enabled', false,
    'show_clock', true,
    'show_personal_greeting', true,
    'show_custom_message', false,
    'custom_message_title', '',
    'custom_message_body', '',
    'show_absence_aggregate', true,
    'show_ticket_stats', true,
    'show_hms_highlights', true,
    'show_attendance_summary', true,
    'show_quick_actions', true,
    'show_activity_feed', true,
    'show_mini_stats_row', true,
    'reveal_names_on_infoscreen', false,
    'show_live_team_board', true,
    'show_tidsbanken_presence', true
  );
$$;

update public.companies c
set kiosk_settings = public.default_kiosk_settings() || coalesce(c.kiosk_settings, '{}'::jsonb);

create or replace function public.set_company_tidsbanken_enabled(p_enabled boolean)
returns boolean
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

  if v_company is null then
    raise exception 'Ingen bedrift for bruker';
  end if;
  if v_role is null or v_role not in ('admin', 'superadmin') then
    raise exception 'Kun administrator kan endre Tidsbanken-integrasjon';
  end if;

  update public.companies
  set tidsbanken_enabled = coalesce(p_enabled, false), updated_at = now()
  where id = v_company;

  return coalesce(p_enabled, false);
end;
$$;

revoke all on function public.set_company_tidsbanken_enabled(boolean) from public;
grant execute on function public.set_company_tidsbanken_enabled(boolean) to authenticated;
