-- Robust onboarding helpers for first-login users
-- Run in Supabase SQL Editor

create or replace function public.get_bootstrap_company_id()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
begin
  -- Prefer company that already has departments configured
  select d.company_id
  into v_company
  from public.departments d
  where d.company_id is not null
  group by d.company_id
  order by count(*) desc
  limit 1;

  if v_company is not null then
    return v_company;
  end if;

  -- Fallback: first company
  select c.id into v_company
  from public.companies c
  order by c.created_at asc
  limit 1;

  return v_company;
end;
$$;

grant execute on function public.get_bootstrap_company_id() to authenticated;

-- Ensure users can update their own profile during onboarding.
drop policy if exists "Brukere kan oppdatere egen profil" on public.profiles;
create policy "Brukere kan oppdatere egen profil"
on public.profiles
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());
