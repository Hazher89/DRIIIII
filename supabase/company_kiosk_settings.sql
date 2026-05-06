-- Infoskjerm / kiosk-innstillinger per selskap (admin styrt).
-- GDPR: standard er aggregerte tall uten navn på delt skjerm.

alter table public.companies
  add column if not exists kiosk_settings jsonb not null default '{}'::jsonb;

comment on column public.companies.kiosk_settings is
  'Synlighet og layout for hjem/infoskjerm. Oppdateres kun via RPC av admin/superadmin.';

create or replace function public.default_kiosk_settings()
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'infoscreen_layout_enabled', false,
    'show_clock', true,
    'show_personal_greeting', true,
    'show_custom_message', false,
    'custom_message_title', '',
    'custom_message_body', '',
    'show_absence_aggregate', true,
    'show_ticket_stats', true,
    'show_hms_highlights', true,
    'show_attendance_summary', true,
    'show_quick_actions', true,
    'show_activity_feed', true,
    'show_mini_stats_row', true,
    'reveal_names_on_infoscreen', false
  );
$$;

-- Backfill tom json til full standard (én gang).
update public.companies
set kiosk_settings = public.default_kiosk_settings()
where kiosk_settings = '{}'::jsonb
   or kiosk_settings is null;

-- Sikrer alle nøkler finnes (merge med standard for eldre rader).
update public.companies c
set kiosk_settings = public.default_kiosk_settings() || coalesce(c.kiosk_settings, '{}'::jsonb);

create or replace function public.set_company_kiosk_settings(p_settings jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_role text;
  merged jsonb;
begin
  select company_id, role::text
    into v_company, v_role
  from public.profiles
  where id = auth.uid();

  if v_company is null then
    raise exception 'Ingen bedrift for bruker';
  end if;

  if v_role is null or v_role not in ('admin', 'superadmin') then
    raise exception 'Kun administrator kan oppdatere infoskjerm';
  end if;

  merged := public.default_kiosk_settings() || coalesce(p_settings, '{}'::jsonb);

  update public.companies
  set
    kiosk_settings = merged,
    updated_at = now()
  where id = v_company;

  return merged;
end;
$$;

revoke all on function public.set_company_kiosk_settings(jsonb) from public;
grant execute on function public.set_company_kiosk_settings(jsonb) to authenticated;
