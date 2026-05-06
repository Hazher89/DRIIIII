-- Route acknowledgement + email outbox notifications

alter table public.partner_route_shares
  add column if not exists ack_status text not null default 'pending',
  add column if not exists ack_at timestamptz,
  add column if not exists ack_by uuid references public.profiles(id) on delete set null,
  add column if not exists ack_comment text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'partner_route_ack_status_check'
  ) then
    alter table public.partner_route_shares
      add constraint partner_route_ack_status_check
      check (ack_status in ('pending', 'accepted', 'rejected'));
  end if;
end $$;

drop policy if exists "partner_route_shares_update" on public.partner_route_shares;
create policy "partner_route_shares_update" on public.partner_route_shares for update
using (
  (
    company_id in (select company_id from public.profiles where id = auth.uid() and company_id is not null)
    and not exists (select 1 from public.profiles x where x.id = auth.uid() and x.partner_id is not null)
  )
  or
  (
    partner_id in (select p.partner_id from public.profiles p where p.id = auth.uid() and p.partner_id is not null)
  )
);

create table if not exists public.email_outbox (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references public.companies(id) on delete cascade,
  to_email text not null,
  subject text not null,
  body text not null,
  category text,
  reference_type text,
  reference_id uuid,
  created_at timestamptz default now(),
  sent_at timestamptz,
  error_message text
);

create index if not exists idx_email_outbox_unsent on public.email_outbox(sent_at) where sent_at is null;

create or replace function public.queue_email(
  p_company_id uuid,
  p_to_email text,
  p_subject text,
  p_body text,
  p_category text default null,
  p_reference_type text default null,
  p_reference_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_to_email is null or length(trim(p_to_email)) = 0 then
    return;
  end if;
  insert into public.email_outbox(
    company_id, to_email, subject, body, category, reference_type, reference_id
  ) values (
    p_company_id, trim(lower(p_to_email)), p_subject, p_body, p_category, p_reference_type, p_reference_id
  );
end;
$$;

grant execute on function public.queue_email(uuid, text, text, text, text, text, uuid) to authenticated, anon;

create or replace function public.notify_leaders_on_absence()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  rec record;
  employee_name text;
begin
  select coalesce(p.full_name, 'Ansatt') into employee_name from public.profiles p where p.id = new.user_id;
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
      'Bruker: ' || employee_name || E'\nType: ' || coalesce(new.type::text, 'ukjent') || E'\nStatus: ' || coalesce(new.status::text, 'ventende'),
      'absence',
      'absences',
      new.id
    );
  end loop;
  return new;
end;
$$;

drop trigger if exists trg_notify_leaders_on_absence on public.absences;
create trigger trg_notify_leaders_on_absence
after insert on public.absences
for each row execute function public.notify_leaders_on_absence();

create or replace function public.notify_leaders_on_ticket()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  rec record;
begin
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
      'Nytt avvik registrert',
      'Tittel: ' || coalesce(new.title, 'uten tittel') || E'\nAlvorlighet: ' || coalesce(new.severity::text, 'middels'),
      'ticket',
      'tickets',
      new.id
    );
  end loop;
  return new;
end;
$$;

drop trigger if exists trg_notify_leaders_on_ticket on public.tickets;
create trigger trg_notify_leaders_on_ticket
after insert on public.tickets
for each row execute function public.notify_leaders_on_ticket();

create or replace function public.notify_partner_on_route_share()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  rec record;
  fallback_partner_email text;
begin
  for rec in
    select login_email as email
    from public.partner_portal_accounts
    where partner_id = new.partner_id
      and is_active = true
      and coalesce(login_email, '') <> ''
  loop
    perform public.queue_email(
      new.company_id,
      rec.email,
      'Ny rute er sendt til dere i DriftPro',
      'Dere har mottatt en ny rute-PDF. Logg inn i DriftPro partnerportal for aa aapne og akseptere/avvise ruten.',
      'partner_route_share',
      'partner_route_shares',
      new.id
    );
  end loop;

  select p.email into fallback_partner_email
  from public.partners p
  where p.id = new.partner_id;

  if fallback_partner_email is not null and length(trim(fallback_partner_email)) > 0 then
    perform public.queue_email(
      new.company_id,
      fallback_partner_email,
      'Ny rute er sendt til dere i DriftPro',
      'Dere har mottatt en ny rute-PDF. Logg inn i DriftPro partnerportal for aa aapne og akseptere/avvise ruten.',
      'partner_route_share',
      'partner_route_shares',
      new.id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_partner_on_route_share on public.partner_route_shares;
create trigger trg_notify_partner_on_route_share
after insert on public.partner_route_shares
for each row execute function public.notify_partner_on_route_share();

create or replace function public.notify_internal_on_route_ack()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  rec record;
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;
  if coalesce(old.ack_status, 'pending') = coalesce(new.ack_status, 'pending') then
    return new;
  end if;

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
      'Rute kvittering fra samarbeidspartner',
      'Rute-id: ' || new.id::text || E'\nStatus: ' || new.ack_status || E'\nKommentar: ' || coalesce(new.ack_comment, '-'),
      'partner_route_ack',
      'partner_route_shares',
      new.id
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_notify_internal_on_route_ack on public.partner_route_shares;
create trigger trg_notify_internal_on_route_ack
after update on public.partner_route_shares
for each row execute function public.notify_internal_on_route_ack();
