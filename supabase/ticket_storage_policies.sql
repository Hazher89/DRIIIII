-- Tickets image storage policies (bucket: tickets)
-- Kjor denne i Supabase SQL Editor for a tillate opplasting av avviksbilder.

insert into storage.buckets (id, name, public)
values ('tickets', 'tickets', true)
on conflict (id) do nothing;

drop policy if exists "tickets_public_read" on storage.objects;
create policy "tickets_public_read"
on storage.objects
for select
using (bucket_id = 'tickets');

drop policy if exists "tickets_auth_upload" on storage.objects;
create policy "tickets_auth_upload"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'tickets'
  and split_part(name, '/', 1) in (
    select p.company_id::text
    from public.profiles p
    where p.id = auth.uid()
      and p.company_id is not null
  )
);

drop policy if exists "tickets_auth_update_own_company" on storage.objects;
create policy "tickets_auth_update_own_company"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'tickets'
  and split_part(name, '/', 1) in (
    select p.company_id::text
    from public.profiles p
    where p.id = auth.uid()
      and p.company_id is not null
  )
)
with check (
  bucket_id = 'tickets'
  and split_part(name, '/', 1) in (
    select p.company_id::text
    from public.profiles p
    where p.id = auth.uid()
      and p.company_id is not null
  )
);

drop policy if exists "tickets_auth_delete_own_company" on storage.objects;
create policy "tickets_auth_delete_own_company"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'tickets'
  and split_part(name, '/', 1) in (
    select p.company_id::text
    from public.profiles p
    where p.id = auth.uid()
      and p.company_id is not null
  )
);
