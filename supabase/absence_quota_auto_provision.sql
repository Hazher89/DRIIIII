-- Oppretter ferie-/fraværssaldo automatisk + gir ledere lesetilgang.

create or replace function public.ensure_absence_quota(
  p_user_id uuid default auth.uid(),
  p_year integer default extract(year from now())::int
)
returns public.absence_quotas
language plpgsql
security definer
set search_path = public
as $$
declare
  _profile public.profiles%rowtype;
  _row public.absence_quotas%rowtype;
begin
  if p_user_id is null then
    raise exception 'Mangler bruker-id';
  end if;

  if p_user_id is distinct from auth.uid()
    and get_user_role() not in ('admin', 'superadmin', 'leder') then
    raise exception 'Ikke tilgang til å opprette saldo for andre';
  end if;

  select * into _profile from public.profiles where id = p_user_id;
  if not found then
    raise exception 'Bruker ikke funnet';
  end if;

  if get_user_role() = 'leder' and p_user_id is distinct from auth.uid() then
    if _profile.department_id is distinct from get_user_department_id() then
      raise exception 'Leder kan kun opprette saldo for egen avdeling';
    end if;
  end if;

  insert into public.absence_quotas (user_id, company_id, year, vacation_days_total)
  values (p_user_id, _profile.company_id, p_year, 25)
  on conflict (user_id, year) do nothing;

  select * into _row from public.absence_quotas
  where user_id = p_user_id and year = p_year;

  return _row;
end;
$$;

grant execute on function public.ensure_absence_quota(uuid, integer) to authenticated;

drop policy if exists "Ledere kan se kvoter i avdeling" on public.absence_quotas;
create policy "Ledere kan se kvoter i avdeling"
  on public.absence_quotas
  for select
  using (
    get_user_role() = 'leder'
    and company_id = get_user_company_id()
    and user_id in (
      select id from public.profiles
      where department_id = get_user_department_id()
    )
  );
