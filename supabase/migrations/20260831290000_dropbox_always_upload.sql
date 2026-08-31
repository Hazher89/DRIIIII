-- Alle innloggede kan forsøke soft-reaktivering ved opplasting
-- (token slettes aldri — kun is_active flippes).

CREATE OR REPLACE FUNCTION public.reactivate_company_dropbox()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID;
BEGIN
  v_company := public.resolve_user_company_id(auth.uid());
  IF v_company IS NULL THEN
    RAISE EXCEPTION 'Ingen bedrift';
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
    RETURN jsonb_build_object('ok', false, 'connected', false, 'reason', 'no_token');
  END IF;

  RETURN jsonb_build_object('ok', true, 'connected', true, 'disconnect_locked', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.reactivate_company_dropbox() TO authenticated;

-- Soft-frakoblede koblinger med token teller som «kan gjenopplives» for health.
-- is_company_dropbox_connected forblir streng (kun aktiv), men opplasting
-- kaller alltid reactivate først + Supabase-sikkerhetsnett i appen.
