-- Staff: unik innlogging-scope, valgfri rutetilgang, push til eier ved stempling (GDPR: kun samme partner).

ALTER TABLE public.partner_staff
  ADD COLUMN IF NOT EXISTS can_manage_routes boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.partner_staff.can_manage_routes IS
  'Når true kan ansatt se/godkjenne ruter for denne partneren. Default: kun stempling.';

-- Stram RLS på ruter: eier-portal ELLER ansatt med eksplisitt grant (ikke alle med partner_id).
DROP POLICY IF EXISTS "partner_route_shares_select" ON public.partner_route_shares;
CREATE POLICY "partner_route_shares_select" ON public.partner_route_shares FOR SELECT USING (
  (
    company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
  )
  OR partner_id IN (
    SELECT ppa.partner_id FROM public.partner_portal_accounts ppa
    WHERE ppa.profile_id = auth.uid()
      AND ppa.is_active = true
      AND ppa.account_kind = 'owner'
  )
  OR partner_id IN (
    SELECT s.partner_id FROM public.partner_staff s
    WHERE s.profile_id = auth.uid()
      AND s.is_active = true
      AND s.can_manage_routes = true
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
    AND partner_vehicle_id IN (
      SELECT p.partner_vehicle_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
  )
);

DROP POLICY IF EXISTS "partner_route_shares_update" ON public.partner_route_shares;
CREATE POLICY "partner_route_shares_update" ON public.partner_route_shares FOR UPDATE USING (
  (
    company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
  )
  OR partner_id IN (
    SELECT ppa.partner_id FROM public.partner_portal_accounts ppa
    WHERE ppa.profile_id = auth.uid()
      AND ppa.is_active = true
      AND ppa.account_kind = 'owner'
  )
  OR partner_id IN (
    SELECT s.partner_id FROM public.partner_staff s
    WHERE s.profile_id = auth.uid()
      AND s.is_active = true
      AND s.can_manage_routes = true
  )
  OR (
    partner_id IN (
      SELECT p.partner_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
    AND partner_vehicle_id IN (
      SELECT p.partner_vehicle_id FROM public.profiles p
      WHERE p.id = auth.uid() AND p.partner_vehicle_id IS NOT NULL
    )
  )
);

CREATE OR REPLACE FUNCTION public.queue_partner_workforce_punch_push(
  p_company_id uuid,
  p_partner_id uuid,
  p_profile_id uuid,
  p_fcm_token text,
  p_title text,
  p_body text,
  p_entry_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_id uuid;
  tok text := trim(coalesce(p_fcm_token, ''));
BEGIN
  IF tok = '' OR p_profile_id IS NULL OR p_entry_id IS NULL OR p_partner_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- GDPR: aldri queue utenfor denne partneren / profilen.
  IF EXISTS (
    SELECT 1 FROM public.push_outbox o
    WHERE o.reference_type = 'partner_time_entries'
      AND o.reference_id = p_entry_id
      AND o.fcm_token = tok
      AND o.created_at > now() - interval '5 minutes'
  ) THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.push_outbox (
    company_id, profile_id, fcm_token, title, body, data,
    category, reference_type, reference_id, description
  ) VALUES (
    p_company_id,
    p_profile_id,
    tok,
    left(trim(p_title), 120),
    left(trim(p_body), 500),
    jsonb_build_object(
      'type', 'partner_staff_punch',
      'partner_id', p_partner_id::text,
      'entry_id', p_entry_id::text
    ),
    'partner_staff_punch',
    'partner_time_entries',
    p_entry_id,
    'Partner-ansatt stempling → bil-eier (kun samme firma)'
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_partner_staff_punch_owners(
  p_partner_id uuid,
  p_company_id uuid,
  p_entry_id uuid,
  p_staff_name text,
  p_action text
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d record;
  n int := 0;
  sent text[] := ARRAY[]::text[];
  v_title text;
  v_body text;
BEGIN
  IF p_action = 'punch_out' THEN
    v_title := 'Stemplet ut';
    v_body := coalesce(nullif(trim(p_staff_name), ''), 'Ansatt') || ' har stemplet ut.';
  ELSE
    v_title := 'Stemplet inn';
    v_body := coalesce(nullif(trim(p_staff_name), ''), 'Ansatt') || ' har stemplet inn.';
  END IF;

  -- Kun aktive bil-eiere for DENNE partneren (ingen kryss mellom firma).
  FOR d IN
    SELECT DISTINCT ON (upd.fcm_token)
      ppa.profile_id,
      upd.fcm_token
    FROM public.partner_portal_accounts ppa
    JOIN public.user_push_devices upd
      ON upd.profile_id = ppa.profile_id
     AND upd.is_active = true
    JOIN public.profiles pr ON pr.id = ppa.profile_id AND coalesce(pr.is_active, true) = true
    WHERE ppa.partner_id = p_partner_id
      AND ppa.is_active = true
      AND ppa.account_kind = 'owner'
      AND ppa.profile_id IS NOT NULL
    ORDER BY upd.fcm_token, upd.last_seen_at DESC
  LOOP
    IF d.fcm_token IS NOT NULL AND NOT (d.fcm_token = ANY (sent)) THEN
      IF public.queue_partner_workforce_punch_push(
        p_company_id, p_partner_id, d.profile_id, d.fcm_token, v_title, v_body, p_entry_id
      ) IS NOT NULL THEN
        n := n + 1;
      END IF;
      sent := array_append(sent, d.fcm_token);
    END IF;
  END LOOP;

  FOR d IN
    SELECT DISTINCT ppa.profile_id, pr.fcm_token
    FROM public.partner_portal_accounts ppa
    JOIN public.profiles pr ON pr.id = ppa.profile_id
    WHERE ppa.partner_id = p_partner_id
      AND ppa.is_active = true
      AND ppa.account_kind = 'owner'
      AND ppa.profile_id IS NOT NULL
      AND coalesce(pr.is_active, true) = true
      AND coalesce(trim(pr.fcm_token), '') <> ''
  LOOP
    IF d.fcm_token IS NOT NULL AND NOT (d.fcm_token = ANY (sent)) THEN
      IF public.queue_partner_workforce_punch_push(
        p_company_id, p_partner_id, d.profile_id, d.fcm_token, v_title, v_body, p_entry_id
      ) IS NOT NULL THEN
        n := n + 1;
      END IF;
      sent := array_append(sent, d.fcm_token);
    END IF;
  END LOOP;

  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_workforce_punch()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_staff public.partner_staff%ROWTYPE;
  v_open public.partner_time_entries%ROWTYPE;
  v_new public.partner_time_entries%ROWTYPE;
  v_action text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_staff
  FROM public.partner_staff s
  WHERE s.profile_id = v_uid AND s.is_active = true
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ingen aktiv ansatt-profil for stempling';
  END IF;

  IF NOT public.partner_workforce_is_enabled(v_staff.partner_id) THEN
    RAISE EXCEPTION 'Stempling er ikke aktivert for denne bedriften';
  END IF;

  SELECT * INTO v_open
  FROM public.partner_time_entries e
  WHERE e.staff_id = v_staff.id
    AND e.is_deleted = false
    AND e.clock_out IS NULL
  ORDER BY e.clock_in DESC
  LIMIT 1;

  IF FOUND THEN
    UPDATE public.partner_time_entries
    SET clock_out = now(),
        updated_at = now(),
        updated_by = v_uid,
        source = 'mobile'
    WHERE id = v_open.id
    RETURNING * INTO v_new;
    v_action := 'punch_out';
  ELSE
    INSERT INTO public.partner_time_entries (
      partner_id, company_id, staff_id, clock_in, source, created_by, updated_by
    ) VALUES (
      v_staff.partner_id, v_staff.company_id, v_staff.id, now(), 'mobile', v_uid, v_uid
    )
    RETURNING * INTO v_new;
    v_action := 'punch_in';
  END IF;

  PERFORM public.notify_partner_staff_punch_owners(
    v_staff.partner_id,
    v_staff.company_id,
    v_new.id,
    v_staff.full_name,
    v_action
  );

  RETURN jsonb_build_object(
    'action', v_action,
    'entry', public._partner_time_entry_snapshot(v_new)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_staff_set_can_manage_routes(
  p_staff_id uuid,
  p_enabled boolean
)
RETURNS public.partner_staff
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff public.partner_staff%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_staff FROM public.partner_staff WHERE id = p_staff_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ansatt ikke funnet';
  END IF;

  IF NOT public.partner_staff_can_manage(v_staff.partner_id, v_staff.company_id) THEN
    RAISE EXCEPTION 'Mangler tilgang';
  END IF;

  UPDATE public.partner_staff
  SET can_manage_routes = coalesce(p_enabled, false),
      updated_at = now()
  WHERE id = p_staff_id
  RETURNING * INTO v_staff;

  RETURN v_staff;
END;
$$;

GRANT EXECUTE ON FUNCTION public.queue_partner_workforce_punch_push(uuid, uuid, uuid, text, text, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.notify_partner_staff_punch_owners(uuid, uuid, uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.partner_staff_set_can_manage_routes(uuid, boolean) TO authenticated;

-- GDPR: portalbrukere ser kun egen partner (ikke alle staff i company).
DROP POLICY IF EXISTS partner_staff_select ON public.partner_staff;
CREATE POLICY partner_staff_select ON public.partner_staff
  FOR SELECT TO authenticated
  USING (
    (
      company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
      AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
    )
    OR profile_id = auth.uid()
    OR partner_id IN (
      SELECT partner_id FROM public.partner_portal_accounts
      WHERE profile_id = auth.uid() AND is_active AND account_kind = 'owner'
    )
  );

DROP POLICY IF EXISTS partner_time_entries_select ON public.partner_time_entries;
CREATE POLICY partner_time_entries_select ON public.partner_time_entries
  FOR SELECT TO authenticated
  USING (
    (
      company_id IN (SELECT company_id FROM public.profiles WHERE id = auth.uid() AND company_id IS NOT NULL)
      AND NOT EXISTS (SELECT 1 FROM public.profiles x WHERE x.id = auth.uid() AND x.partner_id IS NOT NULL)
    )
    OR staff_id IN (SELECT id FROM public.partner_staff WHERE profile_id = auth.uid())
    OR partner_id IN (
      SELECT partner_id FROM public.partner_portal_accounts
      WHERE profile_id = auth.uid() AND is_active AND account_kind = 'owner'
    )
  );
