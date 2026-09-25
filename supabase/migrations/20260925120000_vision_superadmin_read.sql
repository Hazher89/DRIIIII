-- Superadmin must see vision clips across companies (Dropbox OAuth may live on
-- Demo while sorting cameras/events belong to MAVI 00000000).

drop policy if exists vision_events_select_company on public.vision_events;
create policy vision_events_select_company
  on public.vision_events
  for select
  to authenticated
  using (
    company_id = (select company_id from public.profiles where id = auth.uid())
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'superadmin'::public.user_role
    )
  );

drop policy if exists vision_cameras_select_company on public.vision_cameras;
create policy vision_cameras_select_company
  on public.vision_cameras
  for select
  to authenticated
  using (
    company_id = (select company_id from public.profiles where id = auth.uid())
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'superadmin'::public.user_role
    )
  );
