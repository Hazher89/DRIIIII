-- Push-varsel når forside-innhold publiseres (MAVI ansatte eller partnere).

CREATE OR REPLACE FUNCTION public.notify_home_feed_published(
  p_item_id UUID,
  p_with_notification BOOLEAN DEFAULT true
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  h RECORD;
  rec RECORD;
  n INT := 0;
  push_title TEXT;
  push_body TEXT;
  v_partner_scope BOOLEAN;
  v_setting_key TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  IF NOT public.user_can_manage_home_feed(auth.uid()) THEN
    RAISE EXCEPTION 'Ingen tilgang til forside-redigering';
  END IF;

  IF NOT coalesce(p_with_notification, false) THEN
    RETURN 0;
  END IF;

  SELECT *
  INTO h
  FROM public.company_home_feed_items
  WHERE id = p_item_id;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  IF h.company_id IS DISTINCT FROM public.get_user_company_id() THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  push_title := 'Nytt på MAVI-forsiden';
  push_body := CASE
    WHEN nullif(trim(h.title), '') IS NOT NULL THEN
      'Nytt innhold er publisert på hovedsiden: ' || left(trim(h.title), 80)
    ELSE
      'Nytt innhold er publisert på MAVI-hovedsiden. Åpne appen for å se det.'
  END;

  v_partner_scope := (h.audience = 'partner');
  v_setting_key := CASE
    WHEN v_partner_scope THEN 'partner_general'
    ELSE 'general'
  END;

  IF v_partner_scope THEN
    FOR rec IN
      SELECT p.id
      FROM public.profiles p
      WHERE p.company_id = h.company_id
        AND coalesce(p.is_active, true)
        AND (
          p.role = 'samarbeidspartner'::public.user_role
          OR p.partner_id IS NOT NULL
        )
    LOOP
      n := n + public.queue_push_to_profile_if_allowed(
        h.company_id,
        rec.id,
        push_title,
        push_body,
        'home_feed',
        'company_home_feed_items',
        h.id,
        v_setting_key,
        'Forside publisert (partner)',
        true,
        jsonb_build_object(
          'type', 'home_feed_published',
          'reference_type', 'company_home_feed_items',
          'reference_id', h.id::text,
          'audience', h.audience
        )
      );
    END LOOP;
  ELSE
    FOR rec IN
      SELECT p.id
      FROM public.profiles p
      WHERE p.company_id = h.company_id
        AND coalesce(p.is_active, true)
        AND p.role IS DISTINCT FROM 'samarbeidspartner'::public.user_role
        AND p.partner_id IS NULL
    LOOP
      n := n + public.queue_push_to_profile_if_allowed(
        h.company_id,
        rec.id,
        push_title,
        push_body,
        'home_feed',
        'company_home_feed_items',
        h.id,
        v_setting_key,
        'Forside publisert (ansatt)',
        false,
        jsonb_build_object(
          'type', 'home_feed_published',
          'reference_type', 'company_home_feed_items',
          'reference_id', h.id::text,
          'audience', h.audience
        )
      );
    END LOOP;
  END IF;

  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_home_feed_published(UUID, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION public.notify_home_feed_published IS
  'Sender push til ansatte (mavi) eller partnere når forside-innhold publiseres med varsel.';
