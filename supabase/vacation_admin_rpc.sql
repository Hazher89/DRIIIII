-- Avansert ferieadministrasjon: overføring per år, enkeltansatt eller hele selskapet.

create or replace function public.carryover_vacation_between_years(
  p_company_id uuid,
  p_from_year integer,
  p_to_year integer default null,
  p_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  _to_year integer := coalesce(p_to_year, p_from_year + 1);
  _company public.companies%rowtype;
  _profile record;
  _from_q public.absence_quotas%rowtype;
  _remaining integer;
  _carry integer;
  _updated integer := 0;
  _total_carry integer := 0;
begin
  if get_user_role() not in ('admin', 'superadmin') then
    raise exception 'Kun admin kan overføre feriedager';
  end if;
  if get_user_company_id() is distinct from p_company_id then
    raise exception 'Feil selskap';
  end if;
  if _to_year <= p_from_year then
    raise exception 'Til-år må være etter fra-år';
  end if;

  select * into _company from public.companies where id = p_company_id;

  for _profile in
    select id, company_id from public.profiles
    where company_id = p_company_id
      and is_active = true
      and role not in ('samarbeidspartner')
      and (p_user_id is null or id = p_user_id)
  loop
    select * into _from_q from public.absence_quotas
    where user_id = _profile.id and year = p_from_year;

    if _from_q is null then
      continue;
    end if;

    _remaining := (_from_q.vacation_days_total + _from_q.vacation_days_carried_over)
      - _from_q.vacation_days_used;
    _carry := least(greatest(_remaining, 0), coalesce(_company.max_vacation_carryover, 14));

    insert into public.absence_quotas (
      user_id, company_id, year,
      vacation_days_total, vacation_days_carried_over
    )
    values (
      _profile.id, _profile.company_id, _to_year,
      coalesce(_from_q.vacation_days_total, 25), _carry
    )
    on conflict (user_id, year) do update set
      vacation_days_carried_over = _carry,
      vacation_days_total = coalesce(
        absence_quotas.vacation_days_total,
        excluded.vacation_days_total
      ),
      updated_at = now();

    _updated := _updated + 1;
    _total_carry := _total_carry + _carry;
  end loop;

  return jsonb_build_object(
    'employees_updated', _updated,
    'total_days_carried', _total_carry,
    'from_year', p_from_year,
    'to_year', _to_year
  );
end;
$$;

grant execute on function public.carryover_vacation_between_years(uuid, integer, integer, uuid)
  to authenticated;
