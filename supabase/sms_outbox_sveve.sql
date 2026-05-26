-- Sveve SMS-kø for avvik, fravær og andre systemvarsler
-- Kjør i Supabase SQL Editor.
--
-- SETUP (Supabase Dashboard → Edge Functions → send-sms-outbox → Secrets):
--   SVEVE_USER     = Sveve-brukernavn (f.eks. mavi)
--   SVEVE_PASSWD   = API-nøkkel fra sveve.no → API → API-nøkkel
--                    (ofte IKKE samme som innloggingspassord)
--   SVEVE_FROM     = Avsendernavn, maks 11 tegn (f.eks. Mavi)
--   SVEVE_TEST     = true  (valgfritt, sender ikke ekte SMS)
--
-- Deploy: supabase functions deploy send-sms-outbox
-- Cron: hvert minutt kall send-sms-outbox (Dashboard → Cron / pg_cron)

-- ── Outbox ─────────────────────────────────────────────────────────────────
create table if not exists public.sms_outbox (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references public.companies(id) on delete cascade,
  to_phone text not null,
  message text not null,
  category text,
  reference_type text,
  reference_id uuid,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  sveve_message_id bigint,
  error_message text,
  attempts int not null default 0
);

create index if not exists idx_sms_outbox_unsent
  on public.sms_outbox (created_at)
  where sent_at is null and attempts < 5;

alter table public.sms_outbox enable row level security;

drop policy if exists "sms_outbox_service_only" on public.sms_outbox;
create policy "sms_outbox_service_only" on public.sms_outbox
  for all using (false) with check (false);

-- ── Telefonnormalisering (Norge) ───────────────────────────────────────────
create or replace function public.normalize_phone_no(p_phone text)
returns text
language plpgsql
immutable
as $$
declare
  d text;
begin
  if p_phone is null or length(trim(p_phone)) = 0 then
    return null;
  end if;
  d := regexp_replace(trim(p_phone), '[^0-9]', '', 'g');
  if d = '' then
    return null;
  end if;
  if length(d) = 8 and d ~ '^[49]' then
    return '47' || d;
  end if;
  if length(d) = 10 and d ~ '^47[49]' then
    return d;
  end if;
  if length(d) = 11 and d ~ '^047[49]' then
    return substring(d from 2);
  end if;
  if length(d) >= 10 and d ~ '^47' then
    return left(d, 11);
  end if;
  return null;
end;
$$;

-- ── Legg SMS i kø ──────────────────────────────────────────────────────────
drop function if exists public.queue_sms(uuid, text, text, text, text, uuid);

create or replace function public.queue_sms(
  p_company_id uuid,
  p_to_phone text,
  p_message text,
  p_category text default null,
  p_reference_type text default null,
  p_reference_id uuid default null,
  p_to_user_id uuid default null,
  p_triggered_by_user_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized text;
  new_id uuid;
begin
  normalized := public.normalize_phone_no(p_to_phone);
  if normalized is null then
    return null;
  end if;
  if p_message is null or length(trim(p_message)) = 0 then
    return null;
  end if;
  insert into public.sms_outbox (
    company_id, to_phone, message, category, reference_type, reference_id,
    to_user_id, triggered_by_user_id
  ) values (
    p_company_id,
    normalized,
    left(trim(p_message), 1071),
    p_category,
    p_reference_type,
    p_reference_id,
    p_to_user_id,
    coalesce(p_triggered_by_user_id, auth.uid())
  )
  returning id into new_id;
  return new_id;
end;
$$;

grant execute on function public.queue_sms(uuid, text, text, text, text, uuid, uuid, uuid) to authenticated, service_role;

-- ── SMS til ledere (avdeling + admin) ──────────────────────────────────────
create or replace function public.queue_sms_to_leaders(
  p_company_id uuid,
  p_department_id uuid,
  p_message text,
  p_category text default null,
  p_reference_type text default null,
  p_reference_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  rec record;
begin
  for rec in
    select distinct phone
    from public.profiles
    where company_id = p_company_id
      and is_active = true
      and is_approved = true
      and role in ('leder', 'admin', 'superadmin')
      and public.normalize_phone_no(phone) is not null
      and (
        role in ('admin', 'superadmin')
        or (role = 'leder' and department_id is not distinct from p_department_id)
      )
  loop
    perform public.queue_sms(
      p_company_id,
      rec.phone,
      p_message,
      p_category,
      p_reference_type,
      p_reference_id
    );
  end loop;
end;
$$;

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

-- ── Nytt fravær → e-post + SMS ─────────────────────────────────────────────
create or replace function public.notify_leaders_on_absence()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  rec record;
  employee_name text;
  sms_body text;
begin
  select coalesce(p.full_name, 'Ansatt') into employee_name
  from public.profiles p where p.id = new.user_id;

  sms_body :=
    'DriftPro: Nytt fravær. '
    || employee_name
    || ', ' || coalesce(new.type::text, '')
    || ' (' || coalesce(new.status::text, '') || ').';

  for rec in
    select email
    from public.profiles
    where company_id = new.company_id
      and role in ('leder', 'admin', 'superadmin')
      and is_active = true
      and coalesce(email, '') <> ''
  loop
    perform public.queue_email(
      new.company_id,
      rec.email,
      'Nytt fravaer registrert',
      'Bruker: ' || employee_name
        || E'\nType: ' || coalesce(new.type::text, 'ukjent')
        || E'\nStatus: ' || coalesce(new.status::text, 'ventende'),
      'absence',
      'absences',
      new.id
    );
  end loop;

  perform public.queue_sms_to_leaders(
    new.company_id,
    new.department_id,
    sms_body,
    'absence',
    'absences',
    new.id
  );

  return new;
end;
$$;

-- ── Fravær godkjent/avvist → SMS til ansatt ──────────────────────────────────
create or replace function public.notify_absence_decision_sms()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _phone text;
  _msg text;
begin
  if tg_op <> 'UPDATE' or old.status <> 'ventende'
    or new.status not in ('godkjent', 'avvist') then
    return new;
  end if;

  select phone into _phone from public.profiles where id = new.user_id;

  _msg :=
    'DriftPro: Fravær (' || new.type::text || ') '
    || case when new.status = 'godkjent' then 'godkjent' else 'avvist' end
    || ' ' || to_char(new.start_date, 'DD.MM')
    || '-' || to_char(new.end_date, 'DD.MM') || '.';

  perform public.queue_sms(
    new.company_id,
    _phone,
    _msg,
    'absence_decision',
    'absences',
    new.id
  );

  return new;
end;
$$;

drop trigger if exists trg_notify_absence_decision_sms on public.absences;
create trigger trg_notify_absence_decision_sms
  after update of status on public.absences
  for each row execute function public.notify_absence_decision_sms();
