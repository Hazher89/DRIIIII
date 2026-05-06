-- Partner portal bootstrap (magic link), dokument-kategori for oppsummering (GDPR: kun delt med aktuell partner)

-- JSON med partner_id + company_id for innlogget bruker basert på partner_portal_accounts.login_email
create or replace function public.resolve_partner_portal_bootstrap()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  em text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  r jsonb;
begin
  if em is null or em = '' then
    return null;
  end if;
  select jsonb_build_object('partner_id', ppa.partner_id, 'company_id', ppa.company_id)
  into r
  from public.partner_portal_accounts ppa
  where lower(ppa.login_email) = em
    and ppa.is_active = true
  limit 1;
  return r;
end;
$$;

grant execute on function public.resolve_partner_portal_bootstrap() to authenticated;

-- Oppdater eksisterende profil når bruker finnes men mangler partner-knytning
create or replace function public.apply_partner_bootstrap_to_profile()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  em text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  p uuid;
  c uuid;
begin
  if uid is null or em is null or em = '' then
    return;
  end if;
  select ppa.partner_id, ppa.company_id
  into p, c
  from public.partner_portal_accounts ppa
  where lower(ppa.login_email) = em
    and ppa.is_active = true
  limit 1;
  if p is null then
    return;
  end if;
  update public.profiles
  set
    partner_id = p,
    company_id = coalesce(company_id, c),
    role = 'samarbeidspartner'::public.user_role,
    is_onboarded = true,
    is_approved = true
  where id = uid
    and (partner_id is distinct from p or role::text is distinct from 'samarbeidspartner');
end;
$$;

grant execute on function public.apply_partner_bootstrap_to_profile() to authenticated;

-- Opprett / oppdatér profil for portalbruker (RLS-sikker vei uten admin-insert)
create or replace function public.ensure_partner_profile_from_portal()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  em text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  p uuid;
  c uuid;
  fn text;
begin
  if uid is null or em = '' then
    return;
  end if;
  select ppa.partner_id, ppa.company_id
  into p, c
  from public.partner_portal_accounts ppa
  where lower(ppa.login_email) = em
    and ppa.is_active = true
  limit 1;
  if p is null then
    return;
  end if;
  fn := coalesce(nullif(trim(split_part(em, '@', 1)), ''), 'Partner');
  insert into public.profiles (
    id, email, full_name, role, company_id, partner_id,
    is_onboarded, is_approved, is_active
  )
  values (
    uid, em, fn, 'samarbeidspartner'::public.user_role, c, p,
    true, true, true
  )
  on conflict (id) do update set
    email = excluded.email,
    partner_id = excluded.partner_id,
    company_id = coalesce(public.profiles.company_id, excluded.company_id),
    role = 'samarbeidspartner'::public.user_role,
    is_onboarded = true,
    is_approved = true,
    is_active = true;
end;
$$;

grant execute on function public.ensure_partner_profile_from_portal() to authenticated;

alter table public.partner_documents
  add column if not exists doc_category text not null default 'general';

alter table public.partner_documents
  drop constraint if exists partner_documents_doc_category_check;

alter table public.partner_documents
  add constraint partner_documents_doc_category_check
  check (doc_category in ('general', 'summary', 'agreement'));
