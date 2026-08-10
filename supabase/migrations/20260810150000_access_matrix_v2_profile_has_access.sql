-- Avansert tilgangsmatrise v2: profile_has_access + backfill av access_settings.

CREATE OR REPLACE FUNCTION public.profile_has_access(
  p_uid UUID,
  p_area TEXT,
  p_action TEXT DEFAULT 'view'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r TEXT;
  settings JSONB;
  area_obj JSONB;
  approved BOOLEAN;
  active BOOLEAN;
BEGIN
  IF p_uid IS NULL OR coalesce(trim(p_area), '') = '' THEN
    RETURN FALSE;
  END IF;

  SELECT role::text, access_settings, is_approved, is_active
  INTO r, settings, approved, active
  FROM public.profiles
  WHERE id = p_uid;

  IF NOT FOUND OR active IS DISTINCT FROM TRUE THEN
    RETURN FALSE;
  END IF;

  IF r = 'superadmin' THEN
    RETURN TRUE;
  END IF;

  IF approved IS DISTINCT FROM TRUE THEN
    RETURN FALSE;
  END IF;

  settings := coalesce(settings, '{}'::jsonb);

  -- v2: { version: 2, areas: { "fravaer": { "view": true, "approve": true } } }
  IF coalesce((settings->>'version')::int, 0) = 2 THEN
    area_obj := settings -> 'areas' -> p_area;
    IF area_obj IS NULL THEN
      RETURN FALSE;
    END IF;
    -- Parent chain must have view
    IF p_area LIKE '%.%' THEN
      IF NOT public.profile_has_access(
        p_uid,
        regexp_replace(p_area, '\.[^.]+$', ''),
        'view'
      ) THEN
        RETURN FALSE;
      END IF;
    END IF;
    RETURN coalesce((area_obj ->> lower(trim(p_action)))::boolean, false);
  END IF;

  -- v1 flat bool map (legacy)
  IF lower(trim(p_action)) IN ('view', 'read', 'les') THEN
    RETURN coalesce((settings ->> p_area)::boolean, false)
      OR coalesce((settings ->> replace(p_area, '.', '_'))::boolean, false);
  END IF;

  -- Map common action keys from v1
  IF lower(trim(p_action)) = 'approve' THEN
    IF p_area LIKE 'fravaer%' THEN
      RETURN coalesce((settings->>'fravaer_godkjenn')::boolean, false);
    END IF;
    IF p_area LIKE 'avvik%' THEN
      RETURN coalesce((settings->>'avvik_godkjenn')::boolean, false);
    END IF;
    IF p_area LIKE 'partners.vehicle_rental%' THEN
      RETURN coalesce((settings->>'partners_vehicle_rental_approve')::boolean, false);
    END IF;
  END IF;

  IF lower(trim(p_action)) = 'create' THEN
    IF p_area = 'partners' THEN
      RETURN coalesce((settings->>'partners_create')::boolean, false);
    END IF;
    IF p_area LIKE 'fravaer%' THEN
      RETURN coalesce((settings->>'fravaer_registrer_andre')::boolean, false)
        OR coalesce((settings->>'fravaer')::boolean, false);
    END IF;
  END IF;

  IF lower(trim(p_action)) = 'edit' THEN
    IF p_area = 'partners' THEN
      RETURN coalesce((settings->>'partners_edit')::boolean, false);
    END IF;
    IF p_area LIKE 'more.ansatte%' OR p_area = 'admin.ansatte_rediger' THEN
      RETURN coalesce((settings->>'ansatte_rediger')::boolean, false);
    END IF;
  END IF;

  IF lower(trim(p_action)) = 'delete' THEN
    IF p_area = 'partners' THEN
      RETURN coalesce((settings->>'partners_delete')::boolean, false);
    END IF;
  END IF;

  RETURN FALSE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.profile_has_access(UUID, TEXT, TEXT)
  TO authenticated, service_role;

-- Convenience: current user
CREATE OR REPLACE FUNCTION public.current_user_has_access(
  p_area TEXT,
  p_action TEXT DEFAULT 'view'
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.profile_has_access(auth.uid(), p_area, p_action);
$$;

GRANT EXECUTE ON FUNCTION public.current_user_has_access(TEXT, TEXT)
  TO authenticated, service_role;

-- Soft enforcement helpers used by sensitive partner delete / leave approve paths
-- (clients still check UI; DB can call these from future RPCs).

COMMENT ON FUNCTION public.profile_has_access(UUID, TEXT, TEXT) IS
  'DriftPro access_settings v2 (areas/actions) with v1 bool fallback. Superadmin always true.';
