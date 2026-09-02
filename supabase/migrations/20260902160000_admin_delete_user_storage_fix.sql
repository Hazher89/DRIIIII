-- Permanent brukersletting: ikke DELETE direkte fra storage.objects (Supabase blokkerer det).
-- Appen sletter filer via Storage API før admin_delete_user_hard kalles.

CREATE OR REPLACE FUNCTION public.admin_list_user_storage_objects(p_user_id uuid)
RETURNS TABLE(bucket_id text, object_name text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  requester_role public.user_role;
  requester_company uuid;
  target_company uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  requester_role := public.get_user_role();
  requester_company := public.get_user_company_id();

  IF requester_role NOT IN ('superadmin'::public.user_role, 'admin'::public.user_role) THEN
    RAISE EXCEPTION 'Kun admin/superadmin';
  END IF;

  SELECT p.company_id INTO target_company
  FROM public.profiles p
  WHERE p.id = p_user_id;

  IF target_company IS NULL THEN
    RETURN;
  END IF;

  IF requester_role IS DISTINCT FROM 'superadmin'::public.user_role
     AND target_company IS DISTINCT FROM requester_company THEN
    RAISE EXCEPTION 'Cannot access user from another company';
  END IF;

  RETURN QUERY
  SELECT o.bucket_id::text, o.name::text
  FROM storage.objects o
  WHERE o.owner = p_user_id
     OR o.name LIKE p_user_id::text || '/%';
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_list_user_storage_objects(uuid) TO authenticated;

-- Admin/superadmin kan slette lagrede filer for brukere i eget selskap (før hard delete).
DROP POLICY IF EXISTS storage_delete_company_admin ON storage.objects;
CREATE POLICY storage_delete_company_admin ON storage.objects
  FOR DELETE TO authenticated
  USING (
    public.get_user_role() = 'superadmin'::public.user_role
    OR (
      public.is_company_admin()
      AND EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = storage.objects.owner
          AND p.company_id = public.get_user_company_id()
      )
    )
    OR (
      public.is_company_admin()
      AND (storage.foldername(name))[1] IN (
        SELECT p2.id::text
        FROM public.profiles p2
        WHERE p2.company_id = public.get_user_company_id()
      )
    )
  );

CREATE OR REPLACE FUNCTION public.admin_delete_user_hard(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  requester_id uuid := auth.uid();
  requester_role public.user_role;
  requester_company uuid;
  target_company uuid;
  target_role public.user_role;
BEGIN
  IF requester_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  requester_role := public.get_user_role();
  requester_company := public.get_user_company_id();

  IF requester_role NOT IN ('superadmin'::public.user_role, 'admin'::public.user_role) THEN
    RAISE EXCEPTION 'Kun admin/superadmin kan slette brukere permanent';
  END IF;

  IF requester_id = target_user_id THEN
    RAISE EXCEPTION 'Cannot delete yourself';
  END IF;

  SELECT p.company_id, p.role
  INTO target_company, target_role
  FROM public.profiles p
  WHERE p.id = target_user_id;

  IF target_company IS NULL THEN
    RAISE EXCEPTION 'Target user not found in profiles';
  END IF;

  IF requester_role IS DISTINCT FROM 'superadmin'::public.user_role
     AND target_company IS DISTINCT FROM requester_company THEN
    RAISE EXCEPTION 'Cannot delete user from another company';
  END IF;

  IF target_role = 'superadmin'::public.user_role
     AND requester_role IS DISTINCT FROM 'superadmin'::public.user_role THEN
    RAISE EXCEPTION 'Only superadmin can delete superadmin';
  END IF;

  DELETE FROM public.department_leaders WHERE profile_id = target_user_id;

  DELETE FROM public.profile_notification_subscriptions
  WHERE profile_id = target_user_id;

  DELETE FROM public.user_push_devices WHERE profile_id = target_user_id;

  -- Storage-filer må slettes via Storage API i appen (admin_list_user_storage_objects).
  DELETE FROM auth.users WHERE id = target_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_delete_user_hard(uuid) TO authenticated;

COMMENT ON FUNCTION public.admin_delete_user_hard(uuid) IS
  'Permanent sletting av auth-bruker. Kjør admin_list_user_storage_objects + Storage API remove først.';
