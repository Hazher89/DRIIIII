-- Alle innloggede brukere må kunne sjekke om bedriften har Dropbox (for opplasting).
create or replace function public.is_company_dropbox_connected()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
begin
  select company_id into v_company
  from public.profiles
  where id = auth.uid();

  if v_company is null then
    return false;
  end if;

  return exists (
    select 1
    from public.company_dropbox_connections
    where company_id = v_company
  );
end;
$$;

revoke all on function public.is_company_dropbox_connected() from public;
grant execute on function public.is_company_dropbox_connected() to authenticated;

comment on function public.is_company_dropbox_connected() is
  'Sant når bedriften har koblet Dropbox — brukes av alle brukere ved filopplasting.';
