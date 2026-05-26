-- Avvik: SMS til valgt saksbehandler, SMS til avsender ved behandling,
-- og RLS slik at tildelt leder alltid ser og kan oppdatere saken.

-- ── RLS: tildelt saksbehandler ─────────────────────────────────────────────
drop policy if exists "tickets_select_scoped" on public.tickets;
create policy "tickets_select_scoped"
on public.tickets
for select
using (
  (
    get_user_role() in ('admin', 'superadmin')
    and company_id = get_user_company_id()
  )
  or (
    get_user_role() = 'leder'
    and company_id = get_user_company_id()
    and (
      department_id = get_user_department_id()
      or reported_by = auth.uid()
      or assigned_to = auth.uid()
    )
  )
  or (
    get_user_role() = 'ansatt'
    and reported_by = auth.uid()
  )
);

drop policy if exists "tickets_update_scoped" on public.tickets;
create policy "tickets_update_scoped"
on public.tickets
for update
using (
  (
    get_user_role() in ('admin', 'superadmin')
    and company_id = get_user_company_id()
  )
  or (
    get_user_role() = 'leder'
    and company_id = get_user_company_id()
    and (
      department_id = get_user_department_id()
      or reported_by = auth.uid()
      or assigned_to = auth.uid()
    )
  )
)
with check (
  (
    get_user_role() in ('admin', 'superadmin')
    and company_id = get_user_company_id()
  )
  or (
    get_user_role() = 'leder'
    and company_id = get_user_company_id()
    and (
      department_id = get_user_department_id()
      or reported_by = auth.uid()
      or assigned_to = auth.uid()
    )
  )
);

-- ── Nytt avvik → SMS + e-post kun til valgt saksbehandler ───────────────────
create or replace function public.notify_leaders_on_ticket()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  reporter_name text;
  assignee_phone text;
  assignee_email text;
  assignee_name text;
  sms_body text;
begin
  select coalesce(full_name, 'Ansatt') into reporter_name
  from public.profiles where id = new.reported_by;

  if new.assigned_to is not null then
    select
      coalesce(full_name, 'Saksbehandler'),
      phone,
      email
    into assignee_name, assignee_phone, assignee_email
    from public.profiles
    where id = new.assigned_to;

    sms_body :=
      'DriftPro: Nytt avvik til deg. «'
      || left(coalesce(new.title, 'Uten tittel'), 50)
      || '». Alvor: ' || coalesce(new.severity::text, 'middels')
      || '. Fra: ' || reporter_name
      || '. Logg inn og behandle saken.';

    perform public.queue_sms(
      new.company_id,
      assignee_phone,
      sms_body,
      'ticket_assigned',
      'tickets',
      new.id,
      new.assigned_to,
      new.reported_by
    );

    if coalesce(assignee_email, '') <> '' then
      perform public.queue_email(
        new.company_id,
        assignee_email,
        'Nytt avvik — handling kreves',
        'Du er valgt som saksbehandler.' || E'\n\n'
          || 'Tittel: ' || coalesce(new.title, 'uten tittel') || E'\n'
          || 'Alvorlighet: ' || coalesce(new.severity::text, 'middels') || E'\n'
          || 'Fra: ' || reporter_name || E'\n\n'
          || 'Logg inn i DriftPro for å behandle avviket.',
        'ticket_assigned',
        'tickets',
        new.id
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_leaders_on_ticket on public.tickets;
create trigger trg_notify_leaders_on_ticket
  after insert on public.tickets
  for each row execute function public.notify_leaders_on_ticket();

-- ── Avvik behandlet → SMS til den som meldte inn ───────────────────────────
create or replace function public.notify_ticket_status_sms()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _phone text;
  _msg text;
  _resolver text;
  _status_no text;
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if old.status is not distinct from new.status
     and old.resolution_comment is not distinct from new.resolution_comment then
    return new;
  end if;

  select coalesce(full_name, 'Leder') into _resolver
  from public.profiles
  where id = coalesce(new.resolved_by, auth.uid());

  _status_no := case new.status::text
    when 'aapen' then 'åpen'
    when 'under_behandling' then 'under behandling'
    when 'tiltak_utfort' then 'tiltak utført'
    when 'lukket' then 'lukket'
    else new.status::text
  end;

  if new.status in ('tiltak_utfort', 'lukket')
     and old.status is distinct from new.status then
    select phone into _phone from public.profiles where id = new.reported_by;

    _msg :=
      'DriftPro: Avvik «' || left(coalesce(new.title, ''), 40) || '» '
      || 'er behandlet (' || _status_no || '). '
      || 'Av: ' || _resolver || '.';

    if coalesce(new.resolution_comment, '') <> '' then
      _msg := _msg || ' ' || left(new.resolution_comment, 120);
    end if;

    perform public.queue_sms(
      new.company_id,
      _phone,
      _msg,
      'ticket_resolved',
      'tickets',
      new.id,
      new.reported_by,
      coalesce(new.resolved_by, auth.uid())
    );
  elsif old.status is distinct from new.status then
    select phone into _phone from public.profiles where id = new.reported_by;

    _msg :=
      'DriftPro: Avvik «' || left(coalesce(new.title, ''), 40) || '» '
      || 'har status «' || _status_no || '».';

    perform public.queue_sms(
      new.company_id,
      _phone,
      _msg,
      'ticket_status',
      'tickets',
      new.id,
      new.reported_by,
      auth.uid()
    );
  end if;

  if new.severity in ('hoy', 'kritisk')
     and new.status = 'aapen'
     and new.assigned_to is not null
     and (old.severity is distinct from new.severity or old.status is distinct from new.status) then
    select phone into _phone from public.profiles where id = new.assigned_to;
    perform public.queue_sms(
      new.company_id,
      _phone,
      'DriftPro KRITISK avvik: ' || coalesce(new.title, 'Uten tittel'),
      'ticket_critical',
      'tickets',
      new.id,
      new.assigned_to,
      auth.uid()
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_ticket_status_sms on public.tickets;
create trigger trg_notify_ticket_status_sms
  after update of status, severity, resolution_comment, resolved_by
  on public.tickets
  for each row execute function public.notify_ticket_status_sms();
