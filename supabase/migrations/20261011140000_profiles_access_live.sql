-- Profiler i realtime, så åpen app henter ny tilgang uten omstart.
-- Lagring av sider går via SECURITY DEFINER så RLS ikke kan svelge oppdateringen.

DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;

ALTER TABLE public.profiles REPLICA IDENTITY FULL;

CREATE OR REPLACE FUNCTION public.set_profile_access_settings(
  p_profile_id UUID,
  p_access_settings JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_role TEXT;
  caller_company UUID;
  target_company UUID;
BEGIN
  IF auth.uid() IS NULL OR p_profile_id IS NULL THEN
    RAISE EXCEPTION 'Fant ikke profilen';
  END IF;

  SELECT role::text, company_id
  INTO caller_role, caller_company
  FROM public.profiles
  WHERE id = auth.uid();

  SELECT company_id
  INTO target_company
  FROM public.profiles
  WHERE id = p_profile_id;

  IF target_company IS NULL AND caller_role IS DISTINCT FROM 'superadmin' THEN
    RAISE EXCEPTION 'Fant ikke profilen';
  END IF;

  IF caller_role IS DISTINCT FROM 'superadmin' THEN
    IF caller_company IS DISTINCT FROM target_company THEN
      RAISE EXCEPTION 'Ingen tilgang til å endre sider';
    END IF;
    IF NOT public.profile_has_access(auth.uid(), 'more.tilgangskontroll', 'view')
       AND NOT public.profile_has_access(auth.uid(), 'admin.ansatte_rediger', 'edit') THEN
      RAISE EXCEPTION 'Ingen tilgang til å endre sider';
    END IF;
  END IF;

  UPDATE public.profiles
  SET access_settings = coalesce(p_access_settings, '{}'::jsonb)
  WHERE id = p_profile_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fant ikke profilen';
  END IF;

  RETURN coalesce(p_access_settings, '{}'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_profile_access_settings(UUID, JSONB)
  TO authenticated;
