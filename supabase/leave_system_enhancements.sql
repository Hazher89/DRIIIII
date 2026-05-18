-- Fravær & ferie: Lovdata-validering, leder-innlegg, varsler ved godkjenning.

-- ── Valider sykt barn ─────────────────────────────────────────────────────
create or replace function public.validate_sykt_barn()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _quota public.absence_quotas%rowtype;
  _days integer;
  _limit integer := 10;
begin
  if new.type != 'sykt_barn' then
    return new;
  end if;

  _days := new.end_date - new.start_date + 1;

  select * into _quota from public.absence_quotas
  where user_id = new.user_id and year = extract(year from new.start_date)::int;

  if _quota is null then
    insert into public.absence_quotas (user_id, company_id, year)
    values (new.user_id, new.company_id, extract(year from new.start_date)::int)
    returning * into _quota;
  end if;

  if (_quota.sykt_barn_days_used + _days) > _limit then
    raise exception 'Sykt-barn-kvoten for % er overskredet (% av % dager)',
      extract(year from new.start_date), _quota.sykt_barn_days_used, _limit;
  end if;

  return new;
end;
$$;

drop trigger if exists validate_sykt_barn_trigger on public.absences;
create trigger validate_sykt_barn_trigger
  before insert on public.absences
  for each row execute function public.validate_sykt_barn();

-- ── Valider ferie (søknad) ────────────────────────────────────────────────
create or replace function public.validate_ferie_quota()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _quota public.absence_quotas%rowtype;
  _days integer;
  _remaining integer;
  _year integer;
begin
  if new.type != 'ferie' then
    return new;
  end if;

  _days := new.end_date - new.start_date + 1;
  _year := coalesce(new.quota_year, extract(year from new.start_date)::int);

  select * into _quota from public.absence_quotas
  where user_id = new.user_id and year = _year;

  if _quota is null then
    raise exception 'Ingen feriekvote for % — kontakt administrator', _year;
  end if;

  _remaining := (_quota.vacation_days_total + _quota.vacation_days_carried_over)
    - _quota.vacation_days_used;

  if new.status = 'godkjent' and _days > _remaining then
    raise exception 'Ikke nok feriedager igjen (% igjen, søker om %)', _remaining, _days;
  end if;

  return new;
end;
$$;

drop trigger if exists validate_ferie_quota_trigger on public.absences;
create trigger validate_ferie_quota_trigger
  before insert or update on public.absences
  for each row execute function public.validate_ferie_quota();

-- ── Egenmelding: også maks 4 perioder ─────────────────────────────────────
create or replace function public.validate_egenmelding()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _quota public.absence_quotas%rowtype;
  _company public.companies%rowtype;
  _days integer;
begin
  if new.type != 'egenmelding' then
    return new;
  end if;

  _days := new.end_date - new.start_date + 1;
  select * into _company from public.companies where id = new.company_id;

  if _days > _company.egenmelding_consecutive_max then
    raise exception 'Egenmelding kan ikke overstige % sammenhengende dager',
      _company.egenmelding_consecutive_max;
  end if;

  select * into _quota from public.absence_quotas
  where user_id = new.user_id and year = extract(year from new.start_date)::int;

  if _quota is null then
    insert into public.absence_quotas (user_id, company_id, year)
    values (new.user_id, new.company_id, extract(year from new.start_date)::int)
    returning * into _quota;
  end if;

  if _quota.egenmelding_periods_used >= 4 then
    raise exception 'Maks 4 egenmeldingsperioder per kalenderår er brukt';
  end if;

  if (_quota.egenmelding_days_used + _days) > _company.egenmelding_days_per_year then
    raise exception 'Egenmeldingskvoten for året er brukt opp (% av % dager)',
      _quota.egenmelding_days_used, _company.egenmelding_days_per_year;
  end if;

  return new;
end;
$$;

-- ── Kvote ved godkjenning (INSERT + UPDATE) ───────────────────────────────
create or replace function public.update_absence_quota()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'godkjent' and (
    tg_op = 'INSERT'
    or old.status is distinct from 'godkjent'
  ) then
    if new.type = 'egenmelding' then
      update public.absence_quotas
      set egenmelding_days_used = egenmelding_days_used + new.total_days,
          egenmelding_periods_used = egenmelding_periods_used + 1
      where user_id = new.user_id and year = new.quota_year;
    elsif new.type = 'ferie' then
      update public.absence_quotas
      set vacation_days_used = vacation_days_used + new.total_days
      where user_id = new.user_id and year = new.quota_year;
    elsif new.type = 'sykt_barn' then
      update public.absence_quotas
      set sykt_barn_days_used = sykt_barn_days_used + new.total_days
      where user_id = new.user_id and year = new.quota_year;
    end if;
  end if;

  if tg_op = 'UPDATE'
    and old.status = 'godkjent'
    and new.status is distinct from 'godkjent' then
    if old.type = 'egenmelding' then
      update public.absence_quotas
      set egenmelding_days_used = greatest(0, egenmelding_days_used - old.total_days),
          egenmelding_periods_used = greatest(0, egenmelding_periods_used - 1)
      where user_id = old.user_id and year = old.quota_year;
    elsif old.type = 'ferie' then
      update public.absence_quotas
      set vacation_days_used = greatest(0, vacation_days_used - old.total_days)
      where user_id = old.user_id and year = old.quota_year;
    elsif old.type = 'sykt_barn' then
      update public.absence_quotas
      set sykt_barn_days_used = greatest(0, sykt_barn_days_used - old.total_days)
      where user_id = old.user_id and year = old.quota_year;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists update_quota_on_approval on public.absences;
create trigger update_quota_on_approval
  after insert or update on public.absences
  for each row execute function public.update_absence_quota();

-- ── Leder/admin kan registrere fravær for ansatte ─────────────────────────
drop policy if exists "absences_insert_manager" on public.absences;
create policy "absences_insert_manager"
on public.absences
for insert
with check (
  (
    get_user_role() in ('admin', 'superadmin')
    and company_id = get_user_company_id()
  )
  or (
    get_user_role() = 'leder'
    and company_id = get_user_company_id()
    and department_id = get_user_department_id()
  )
);

-- ── In-app varsler ────────────────────────────────────────────────────────
create or replace function public.notify_absence_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _employee_name text;
  _approver_name text;
  _dept_leader uuid;
begin
  if tg_op = 'INSERT' and new.status = 'ventende' then
    for _dept_leader in
      select d.leader_id from public.departments d
      where d.id = new.department_id and d.leader_id is not null
    loop
      insert into public.notifications (user_id, company_id, title, body, type, data)
      values (
        _dept_leader,
        new.company_id,
        'Ny fraværssøknad',
        coalesce((select full_name from public.profiles where id = new.user_id), 'Ansatt')
          || ' · ' || new.type::text || ' · ' || new.status::text,
        'push',
        jsonb_build_object('absence_id', new.id, 'kind', 'absence_pending')
      );
    end loop;

    insert into public.notifications (user_id, company_id, title, body, type, data)
    select p.id, new.company_id,
      'Ny fraværssøknad',
      coalesce((select full_name from public.profiles where id = new.user_id), 'Ansatt')
        || ' · ' || new.type::text,
      'push',
      jsonb_build_object('absence_id', new.id, 'kind', 'absence_pending')
    from public.profiles p
    where p.company_id = new.company_id
      and p.role in ('admin', 'superadmin')
      and p.is_active = true
      and p.id is distinct from new.user_id;
  end if;

  if tg_op = 'UPDATE' and old.status = 'ventende'
    and new.status in ('godkjent', 'avvist') then
    select coalesce(full_name, 'Leder') into _approver_name
    from public.profiles where id = new.approved_by;

    insert into public.notifications (user_id, company_id, title, body, type, data)
    values (
      new.user_id,
      new.company_id,
      case when new.status = 'godkjent' then 'Fravær godkjent' else 'Fravær avvist' end,
      new.type::text || ' ' || to_char(new.start_date, 'DD.MM')
        || '–' || to_char(new.end_date, 'DD.MM')
        || ' · ' || _approver_name,
      'push',
      jsonb_build_object('absence_id', new.id, 'status', new.status::text)
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_absence_status on public.absences;
create trigger trg_notify_absence_status
  after insert or update on public.absences
  for each row execute function public.notify_absence_status_change();

-- ── E-post ved godkjenning/avslag ─────────────────────────────────────────
create or replace function public.notify_absence_decision_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _email text;
  _subject text;
begin
  if tg_op = 'UPDATE' and old.status = 'ventende'
    and new.status in ('godkjent', 'avvist') then
    select email into _email from public.profiles where id = new.user_id;
    if coalesce(_email, '') = '' then
      return new;
    end if;

    _subject := case
      when new.status = 'godkjent' then 'Fravær godkjent – DriftPro'
      else 'Fravær avvist – DriftPro'
    end;

    perform public.queue_email(
      new.company_id,
      _email,
      _subject,
      'Din søknad (' || new.type::text || ') '
        || to_char(new.start_date, 'YYYY-MM-DD') || ' til '
        || to_char(new.end_date, 'YYYY-MM-DD')
        || ' er ' || new.status::text || '.',
      'absence',
      'absences',
      new.id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_absence_decision_email on public.absences;
create trigger trg_notify_absence_decision_email
  after update on public.absences
  for each row execute function public.notify_absence_decision_email();

-- ── Admin: del ut feriedager til alle aktive ────────────────────────────────
create or replace function public.distribute_vacation_days(
  p_company_id uuid,
  p_year integer,
  p_days integer
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  _count integer := 0;
  _profile record;
begin
  if get_user_role() not in ('admin', 'superadmin') then
    raise exception 'Kun admin kan dele ut feriedager';
  end if;
  if get_user_company_id() is distinct from p_company_id then
    raise exception 'Feil selskap';
  end if;

  for _profile in
    select id from public.profiles
    where company_id = p_company_id and is_active = true
      and role not in ('samarbeidspartner')
  loop
    insert into public.absence_quotas (user_id, company_id, year, vacation_days_total)
    values (_profile.id, p_company_id, p_year, p_days)
    on conflict (user_id, year)
    do update set vacation_days_total = p_days, updated_at = now();
    _count := _count + 1;
  end loop;

  return _count;
end;
$$;

grant execute on function public.distribute_vacation_days(uuid, integer, integer) to authenticated;

-- ── Årlig overføring: behold tildeling + legg til rest ─────────────────────
create or replace function public.annual_vacation_carryover()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _profile record;
  _quota public.absence_quotas%rowtype;
  _company public.companies%rowtype;
  _remaining integer;
  _carryover integer;
  _new_year integer := extract(year from now())::int;
  _old_year integer := _new_year - 1;
  _default_days integer := 25;
begin
  for _profile in
    select * from public.profiles where is_active = true
      and role not in ('samarbeidspartner')
  loop
    select * into _quota from public.absence_quotas
    where user_id = _profile.id and year = _old_year;

    select * into _company from public.companies where id = _profile.company_id;

    if _quota is not null then
      _remaining := (_quota.vacation_days_total + _quota.vacation_days_carried_over)
        - _quota.vacation_days_used;
      _carryover := least(greatest(_remaining, 0), coalesce(_company.max_vacation_carryover, 14));
      _default_days := coalesce(_quota.vacation_days_total, 25);
    else
      _carryover := 0;
    end if;

    insert into public.absence_quotas (
      user_id, company_id, year,
      vacation_days_total, vacation_days_carried_over
    )
    values (_profile.id, _profile.company_id, _new_year, _default_days, _carryover)
    on conflict (user_id, year) do update set
      vacation_days_carried_over = excluded.vacation_days_carried_over,
      vacation_days_total = coalesce(absence_quotas.vacation_days_total, excluded.vacation_days_total),
      updated_at = now();
  end loop;
end;
$$;
