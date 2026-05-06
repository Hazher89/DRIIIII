-- Flåte / rute-skift (Connecteam-lignende), snapshot per bil+dag+skift, kobling på rute-PDF

create table if not exists public.fleet_shift_definitions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  description text,
  color_hex text not null default '#2E7D32',
  region_group text,
  time_band text,
  shift_kind text not null default 'route_ops'
    check (shift_kind in ('route_ops', 'availability')),
  sort_order int not null default 0,
  is_archived boolean not null default false,
  created_at timestamptz default now()
);

create index if not exists idx_fleet_shifts_company_live
  on public.fleet_shift_definitions(company_id) where not is_archived;

alter table public.partner_route_shares
  add column if not exists shift_id uuid references public.fleet_shift_definitions(id) on delete set null;

alter table public.partner_route_shares
  add column if not exists partner_vehicle_id uuid references public.partner_vehicles(id) on delete set null;

create index if not exists idx_route_shares_vehicle on public.partner_route_shares(partner_vehicle_id);
create index if not exists idx_route_shares_shift on public.partner_route_shares(shift_id);

create table if not exists public.partner_vehicle_fleet_snapshots (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  partner_vehicle_id uuid not null references public.partner_vehicles(id) on delete cascade,
  snapshot_date date not null,
  shift_id uuid not null references public.fleet_shift_definitions(id) on delete cascade,
  status text not null check (status in ('har_rute', 'ledig', 'fri', 'gitt_bort')),
  partner_route_share_id uuid references public.partner_route_shares(id) on delete set null,
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(partner_vehicle_id, snapshot_date, shift_id)
);

create index if not exists idx_fleet_snap_company_date on public.partner_vehicle_fleet_snapshots(company_id, snapshot_date);

alter table public.fleet_shift_definitions enable row level security;
alter table public.partner_vehicle_fleet_snapshots enable row level security;

drop policy if exists "fleet_shift_definitions_select" on public.fleet_shift_definitions;
create policy "fleet_shift_definitions_select" on public.fleet_shift_definitions for select using (
  company_id in (select p.company_id from public.profiles p where p.id = auth.uid() and p.company_id is not null)
  and not exists (select 1 from public.profiles x where x.id = auth.uid() and x.partner_id is not null)
);

drop policy if exists "fleet_shift_definitions_manage" on public.fleet_shift_definitions;
create policy "fleet_shift_definitions_manage" on public.fleet_shift_definitions for all using (
  company_id in (select p.company_id from public.profiles p where p.id = auth.uid() and p.company_id is not null)
  and not exists (select 1 from public.profiles x where x.id = auth.uid() and x.partner_id is not null)
) with check (
  company_id in (select p.company_id from public.profiles p where p.id = auth.uid() and p.company_id is not null)
  and not exists (select 1 from public.profiles x where x.id = auth.uid() and x.partner_id is not null)
);

drop policy if exists "fleet_snapshots_select" on public.partner_vehicle_fleet_snapshots;
create policy "fleet_snapshots_select" on public.partner_vehicle_fleet_snapshots for select using (
  company_id in (select p.company_id from public.profiles p where p.id = auth.uid() and p.company_id is not null)
  and not exists (select 1 from public.profiles x where x.id = auth.uid() and x.partner_id is not null)
);

drop policy if exists "fleet_snapshots_manage" on public.partner_vehicle_fleet_snapshots;
create policy "fleet_snapshots_manage" on public.partner_vehicle_fleet_snapshots for all using (
  company_id in (select p.company_id from public.profiles p where p.id = auth.uid() and p.company_id is not null)
  and not exists (select 1 from public.profiles x where x.id = auth.uid() and x.partner_id is not null)
) with check (
  company_id in (select p.company_id from public.profiles p where p.id = auth.uid() and p.company_id is not null)
  and not exists (select 1 from public.profiles x where x.id = auth.uid() and x.partner_id is not null)
);
