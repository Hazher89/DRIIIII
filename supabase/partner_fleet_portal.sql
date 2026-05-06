-- Partner fleet units (M01+) and portal usernames

create table if not exists public.partner_vehicles (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  unit_code text not null,
  registration_number text not null,
  notes text,
  created_at timestamptz default now()
);

create index if not exists idx_partner_vehicles_partner on public.partner_vehicles(partner_id);
create unique index if not exists uq_partner_vehicle_unit on public.partner_vehicles(partner_id, unit_code);

create table if not exists public.partner_portal_accounts (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  username text not null,
  login_email text not null,
  profile_id uuid references public.profiles(id) on delete set null,
  is_active boolean default true,
  created_at timestamptz default now()
);

create unique index if not exists uq_partner_portal_username on public.partner_portal_accounts(lower(username));
create unique index if not exists uq_partner_portal_email on public.partner_portal_accounts(lower(login_email));

alter table public.partner_vehicles enable row level security;
alter table public.partner_portal_accounts enable row level security;

drop policy if exists "partner_vehicles_select" on public.partner_vehicles;
create policy "partner_vehicles_select" on public.partner_vehicles for select using (
  company_id in (select p.company_id from public.profiles p where p.id = auth.uid())
  or partner_id in (select p.partner_id from public.profiles p where p.id = auth.uid() and p.partner_id is not null)
);

drop policy if exists "partner_vehicles_manage" on public.partner_vehicles;
create policy "partner_vehicles_manage" on public.partner_vehicles for all using (
  company_id in (select p.company_id from public.profiles p where p.id = auth.uid())
  and not exists (select 1 from public.profiles x where x.id = auth.uid() and x.partner_id is not null)
) with check (
  company_id in (select p.company_id from public.profiles p where p.id = auth.uid())
  and not exists (select 1 from public.profiles x where x.id = auth.uid() and x.partner_id is not null)
);

drop policy if exists "partner_portal_accounts_select" on public.partner_portal_accounts;
create policy "partner_portal_accounts_select" on public.partner_portal_accounts for select using (
  company_id in (select p.company_id from public.profiles p where p.id = auth.uid())
  or partner_id in (select p.partner_id from public.profiles p where p.id = auth.uid() and p.partner_id is not null)
);

drop policy if exists "partner_portal_accounts_manage" on public.partner_portal_accounts;
create policy "partner_portal_accounts_manage" on public.partner_portal_accounts for all using (
  company_id in (select p.company_id from public.profiles p where p.id = auth.uid())
  and not exists (select 1 from public.profiles x where x.id = auth.uid() and x.partner_id is not null)
) with check (
  company_id in (select p.company_id from public.profiles p where p.id = auth.uid())
  and not exists (select 1 from public.profiles x where x.id = auth.uid() and x.partner_id is not null)
);

create or replace function public.resolve_partner_login_email(p_username text)
returns text
language sql
security definer
set search_path = public
as $$
  select ppa.login_email
  from public.partner_portal_accounts ppa
  where lower(ppa.username) = lower(p_username)
    and ppa.is_active = true
  limit 1
$$;

grant execute on function public.resolve_partner_login_email(text) to anon, authenticated;
