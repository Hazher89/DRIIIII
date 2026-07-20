-- Dropbox skal aldri «falle ut» ved et uhell:
-- 1) Tilkobling er låst mot frakobling (standard)
-- 2) Frakobling sletter ALDRI refresh_token — kun soft-deaktivering når ulåst
-- 3) Helsefelter for periodisk token-refresh / overvåking

CREATE OR REPLACE FUNCTION public.resolve_user_company_id(p_uid UUID DEFAULT auth.uid())
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID;
BEGIN
  IF p_uid IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT company_id INTO v_company
  FROM public.profiles
  WHERE id = p_uid;

  IF v_company IS NOT NULL THEN
    RETURN v_company;
  END IF;

  BEGIN
    SELECT public.get_bootstrap_company_id() INTO v_company;
  EXCEPTION
    WHEN OTHERS THEN
      v_company := NULL;
  END;

  IF v_company IS NOT NULL THEN
    RETURN v_company;
  END IF;

  SELECT company_id INTO v_company
  FROM public.departments
  WHERE company_id IS NOT NULL
  LIMIT 1;

  IF v_company IS NOT NULL THEN
    RETURN v_company;
  END IF;

  SELECT id INTO v_company FROM public.companies LIMIT 1;
  RETURN v_company;
END;
$$;

ALTER TABLE public.company_dropbox_connections
  ADD COLUMN IF NOT EXISTS disconnect_locked BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS last_health_ok_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_health_error TEXT,
  ADD COLUMN IF NOT EXISTS health_fail_count INT NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.company_dropbox_connections.disconnect_locked IS
  'Når true kan ingen koble fra Dropbox via appen uten å låse opp først.';
COMMENT ON COLUMN public.company_dropbox_connections.is_active IS
  'Soft-frakobling. refresh_token beholdes alltid for rask reaktivering.';

UPDATE public.company_dropbox_connections
SET
  disconnect_locked = true,
  is_active = true
WHERE true;

CREATE OR REPLACE FUNCTION public.is_company_dropbox_connected()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID;
BEGIN
  v_company := public.resolve_user_company_id(auth.uid());
  IF v_company IS NULL THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.company_dropbox_connections c
    WHERE c.company_id = v_company
      AND c.is_active = true
      AND coalesce(trim(c.refresh_token), '') <> ''
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_company_dropbox_status()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID;
  v_role TEXT;
  row public.company_dropbox_connections%ROWTYPE;
BEGIN
  SELECT role::text INTO v_role FROM public.profiles WHERE id = auth.uid();
  v_company := public.resolve_user_company_id(auth.uid());

  IF v_company IS NULL THEN
    RAISE EXCEPTION 'Ingen bedrift';
  END IF;
  IF v_role IS NULL OR v_role NOT IN ('admin', 'superadmin') THEN
    RAISE EXCEPTION 'Kun administrator';
  END IF;

  SELECT * INTO row
  FROM public.company_dropbox_connections
  WHERE company_id = v_company;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('connected', false, 'disconnect_locked', true);
  END IF;

  RETURN jsonb_build_object(
    'connected', row.is_active AND coalesce(trim(row.refresh_token), '') <> '',
    'account_email', row.account_email,
    'root_folder', row.root_folder,
    'large_file_threshold_bytes', row.large_file_threshold_bytes,
    'connected_at', row.connected_at,
    'disconnect_locked', row.disconnect_locked,
    'is_active', row.is_active,
    'last_health_ok_at', row.last_health_ok_at,
    'last_health_error', row.last_health_error,
    'health_fail_count', row.health_fail_count,
    'needs_reauth', coalesce(row.health_fail_count, 0) >= 3
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.disconnect_company_dropbox()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID;
  v_role TEXT;
  v_locked BOOLEAN;
BEGIN
  SELECT role::text INTO v_role FROM public.profiles WHERE id = auth.uid();
  v_company := public.resolve_user_company_id(auth.uid());

  IF v_role IS NULL OR v_role NOT IN ('admin', 'superadmin') THEN
    RAISE EXCEPTION 'Kun administrator';
  END IF;
  IF v_company IS NULL THEN
    RAISE EXCEPTION 'Ingen bedrift';
  END IF;

  SELECT disconnect_locked INTO v_locked
  FROM public.company_dropbox_connections
  WHERE company_id = v_company;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF coalesce(v_locked, true) THEN
    RAISE EXCEPTION
      'Dropbox er låst mot frakobling. Lås opp under Fillagring først (kun superadmin).';
  END IF;

  UPDATE public.company_dropbox_connections
  SET
    is_active = false,
    updated_at = now()
  WHERE company_id = v_company;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_company_dropbox_disconnect_lock(
  p_locked BOOLEAN,
  p_confirm TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID;
  v_role TEXT;
BEGIN
  SELECT role::text INTO v_role FROM public.profiles WHERE id = auth.uid();
  v_company := public.resolve_user_company_id(auth.uid());

  IF v_role IS DISTINCT FROM 'superadmin' THEN
    RAISE EXCEPTION 'Kun superadmin kan endre Dropbox-lås';
  END IF;
  IF v_company IS NULL THEN
    RAISE EXCEPTION 'Ingen bedrift';
  END IF;

  IF p_locked IS NOT TRUE THEN
    IF upper(trim(coalesce(p_confirm, ''))) IS DISTINCT FROM 'LÅS OPP DROPBOX' THEN
      RAISE EXCEPTION 'Skriv nøyaktig: LÅS OPP DROPBOX';
    END IF;
  END IF;

  UPDATE public.company_dropbox_connections
  SET
    disconnect_locked = coalesce(p_locked, true),
    updated_at = now()
  WHERE company_id = v_company;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Dropbox er ikke koblet';
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'disconnect_locked', coalesce(p_locked, true)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.reactivate_company_dropbox()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID;
  v_role TEXT;
BEGIN
  SELECT role::text INTO v_role FROM public.profiles WHERE id = auth.uid();
  v_company := public.resolve_user_company_id(auth.uid());

  IF v_role IS NULL OR v_role NOT IN ('admin', 'superadmin') THEN
    RAISE EXCEPTION 'Kun administrator';
  END IF;

  UPDATE public.company_dropbox_connections
  SET
    is_active = true,
    disconnect_locked = true,
    health_fail_count = 0,
    last_health_error = NULL,
    updated_at = now()
  WHERE company_id = v_company
    AND coalesce(trim(refresh_token), '') <> '';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ingen lagret Dropbox-tilkobling å reaktivere — koble via OAuth';
  END IF;

  RETURN jsonb_build_object('ok', true, 'connected', true, 'disconnect_locked', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_company_dropbox_disconnect_lock(BOOLEAN, TEXT)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.reactivate_company_dropbox() TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_user_company_id(UUID) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.mark_dropbox_health(
  p_company_id UUID,
  p_ok BOOLEAN,
  p_error TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_ok THEN
    UPDATE public.company_dropbox_connections
    SET
      last_health_ok_at = now(),
      last_health_error = NULL,
      health_fail_count = 0,
      updated_at = now()
    WHERE company_id = p_company_id;
  ELSE
    UPDATE public.company_dropbox_connections
    SET
      last_health_error = left(coalesce(p_error, 'ukjent'), 500),
      health_fail_count = least(coalesce(health_fail_count, 0) + 1, 99),
      updated_at = now()
    WHERE company_id = p_company_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_dropbox_health(UUID, BOOLEAN, TEXT) TO service_role;

CREATE OR REPLACE FUNCTION public.invoke_dropbox_keepalive()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_base TEXT := 'https://ksnnyccthotjbrmgjgdc.supabase.co';
  v_anon TEXT := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtzbm55Y2N0aG90amJybWdqZ2RjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE4NDUzOTAsImV4cCI6MjA4NzQyMTM5MH0.P-TU43MSVNcTATUZkg6FLk4Mb1c0CclgPX6VjvvDul8';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := v_base || '/functions/v1/dropbox-storage?action=keepalive',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_anon,
      'apikey', v_anon
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      PERFORM cron.unschedule('driftpro-dropbox-keepalive');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    PERFORM cron.schedule(
      'driftpro-dropbox-keepalive',
      '0 */12 * * *',
      $cron$SELECT public.invoke_dropbox_keepalive();$cron$
    );
  END IF;
END;
$$;
