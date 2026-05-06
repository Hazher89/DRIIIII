-- Bootstrap policies for company lookup on first login.
-- Required so onboarding can resolve company/department for fresh OAuth users.

alter table public.companies enable row level security;

drop policy if exists "companies_auth_select" on public.companies;
create policy "companies_auth_select"
on public.companies
for select
to authenticated
using (true);

-- Optional one-time backfill for profiles missing company_id (single-tenant style).
-- Picks the company that currently has departments, otherwise first available company.
with candidate as (
  select company_id as id
  from public.departments
  where company_id is not null
  group by company_id
  order by count(*) desc
  limit 1
), fallback_company as (
  select coalesce(
    (select id from candidate),
    (select id from public.companies order by created_at asc limit 1)
  ) as id
)
update public.profiles p
set company_id = f.id
from fallback_company f
where p.company_id is null
  and f.id is not null;
