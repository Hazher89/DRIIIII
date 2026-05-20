-- Permanent user delete for superadmin only.
-- Sletter fra auth.users -> cascader til profiles og relaterte data.

create or replace function public.admin_delete_user_hard(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  requester_id uuid := auth.uid();
  requester_role text;
  requester_company uuid;
  target_company uuid;
  target_role text;
begin
  if requester_id is null then
    raise exception 'Not authenticated';
  end if;

  select p.role::text, p.company_id
  into requester_role, requester_company
  from public.profiles p
  where p.id = requester_id;

  if requester_role is distinct from 'superadmin' then
    raise exception 'Only superadmin can delete users';
  end if;

  if requester_id = target_user_id then
    raise exception 'Cannot delete yourself';
  end if;

  select p.company_id, p.role::text
  into target_company, target_role
  from public.profiles p
  where p.id = target_user_id;

  if target_company is null then
    raise exception 'Target user not found in profiles';
  end if;

  if requester_role <> 'superadmin' and requester_company <> target_company then
    raise exception 'Cannot delete user from another company';
  end if;

  if target_role = 'superadmin' and requester_role <> 'superadmin' then
    raise exception 'Only superadmin can delete superadmin';
  end if;

  -- Clean up potential owned files in storage.
  delete from storage.objects where owner = target_user_id;

  -- Hard delete (profiles row is removed by FK cascade).
  delete from auth.users where id = target_user_id;
end;
$$;

revoke all on function public.admin_delete_user_hard(uuid) from public;
grant execute on function public.admin_delete_user_hard(uuid) to authenticated;
