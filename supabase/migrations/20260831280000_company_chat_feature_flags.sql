-- Remote av/på for partner ↔ MAVI chat (uten app/web rebuild).
-- Superadmin styrer separat for MAVI-ansatte og partner-portal.

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS chat_enabled_mavi boolean NOT NULL DEFAULT true;

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS chat_enabled_partners boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.companies.chat_enabled_mavi IS
  'Vis chat for interne MAVI-brukere. Oppdateres live via Supabase Realtime.';

COMMENT ON COLUMN public.companies.chat_enabled_partners IS
  'Vis chat i partnerportalen. Oppdateres live via Supabase Realtime.';

CREATE OR REPLACE FUNCTION public.set_company_chat_enabled(
  p_mavi boolean DEFAULT NULL,
  p_partners boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company uuid;
  v_role text;
BEGIN
  SELECT company_id, role::text
    INTO v_company, v_role
  FROM public.profiles
  WHERE id = auth.uid();

  IF v_company IS NULL THEN
    RAISE EXCEPTION 'Ingen bedrift for bruker';
  END IF;

  IF v_role IS DISTINCT FROM 'superadmin' THEN
    RAISE EXCEPTION 'Kun superadmin kan styre chat-systemet';
  END IF;

  UPDATE public.companies
  SET
    chat_enabled_mavi = coalesce(p_mavi, chat_enabled_mavi),
    chat_enabled_partners = coalesce(p_partners, chat_enabled_partners),
    updated_at = now()
  WHERE id = v_company;

  RETURN jsonb_build_object(
    'ok', true,
    'chat_enabled_mavi', (SELECT chat_enabled_mavi FROM public.companies WHERE id = v_company),
    'chat_enabled_partners', (SELECT chat_enabled_partners FROM public.companies WHERE id = v_company)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_company_chat_enabled(boolean, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_company_chat_enabled(boolean, boolean) TO authenticated;

-- Lesbar for alle innloggede i bedriften (RLS på companies må tillate SELECT company_id match)
CREATE OR REPLACE FUNCTION public.company_chat_flags(p_company_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'chat_enabled_mavi', coalesce(c.chat_enabled_mavi, true),
    'chat_enabled_partners', coalesce(c.chat_enabled_partners, true)
  )
  FROM public.companies c
  WHERE c.id = p_company_id;
$$;

GRANT EXECUTE ON FUNCTION public.company_chat_flags(uuid) TO authenticated;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.companies;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
