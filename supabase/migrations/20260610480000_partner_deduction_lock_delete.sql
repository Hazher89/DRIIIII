-- Bot/Trekk: lås fakturerte saker, opplåsing (Nico/Tommy/Hazher), soft-slett med kommentar.

ALTER TABLE public.partner_deduction_cases
  ADD COLUMN IF NOT EXISTS is_locked BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS locked_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS unlocked_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS unlocked_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS deletion_comment TEXT;

ALTER TABLE public.partner_deduction_cases
  DROP CONSTRAINT IF EXISTS partner_deduction_cases_status_check;

ALTER TABLE public.partner_deduction_cases
  ADD CONSTRAINT partner_deduction_cases_status_check
  CHECK (status IN ('registered', 'notified', 'invoiced', 'deleted'));

UPDATE public.partner_deduction_cases
SET is_locked = true,
    locked_at = coalesce(locked_at, invoiced_at, now())
WHERE status = 'invoiced'
  AND deleted_at IS NULL
  AND is_locked = false;

CREATE OR REPLACE FUNCTION public.can_unlock_partner_deduction_case(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = COALESCE(p_user_id, auth.uid())
      AND (
        coalesce(p.employee_number, '') IN ('25', '100', '144')
        OR lower(p.full_name) LIKE '%tommy%'
        OR lower(p.full_name) LIKE '%hazher%'
        OR lower(p.full_name) LIKE '%nicola%'
        OR lower(p.full_name) LIKE '%nico%'
        OR lower(coalesce(p.email, '')) LIKE '%tommy%'
        OR lower(coalesce(p.email, '')) LIKE '%hazher%'
        OR lower(coalesce(p.email, '')) LIKE '%nico%'
        OR lower(coalesce(p.email, '')) LIKE '%nicola%'
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.mark_partner_deductions_invoiced(
  p_company_id UUID,
  p_case_ids UUID[]
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
  v_profile public.profiles%ROWTYPE;
  v_is_superadmin BOOLEAN := public.get_user_role() = 'superadmin'::public.user_role;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  IF NOT v_is_superadmin AND v_profile.company_id IS DISTINCT FROM p_company_id THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  IF NOT (
    v_is_superadmin
    OR coalesce(v_profile.employee_number, '') = '144'
    OR lower(v_profile.full_name) LIKE '%nicola%'
    OR lower(v_profile.full_name) LIKE '%nico%'
    OR lower(coalesce(v_profile.email, '')) LIKE '%nico%'
    OR lower(coalesce(v_profile.email, '')) LIKE '%nicola%'
  ) THEN
    RAISE EXCEPTION 'Kun økonomi (Nico) kan markere som fakturert';
  END IF;

  UPDATE public.partner_deduction_cases
  SET status = 'invoiced',
      invoiced_at = now(),
      invoiced_by = auth.uid(),
      is_locked = true,
      locked_at = now()
  WHERE company_id = p_company_id
    AND id = ANY(p_case_ids)
    AND status <> 'invoiced'
    AND deleted_at IS NULL;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.unlock_partner_deduction_case(p_case_id UUID)
RETURNS public.partner_deduction_cases
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_case public.partner_deduction_cases%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  IF NOT public.can_unlock_partner_deduction_case() THEN
    RAISE EXCEPTION 'Kun Nico, Tommy eller Hazher kan låse opp fakturerte saker';
  END IF;

  SELECT * INTO v_case FROM public.partner_deduction_cases WHERE id = p_case_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sak ikke funnet';
  END IF;

  IF v_case.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Slettede saker kan ikke låses opp';
  END IF;

  IF NOT v_case.is_locked THEN
    RAISE EXCEPTION 'Saken er ikke låst';
  END IF;

  IF v_case.status <> 'invoiced' THEN
    RAISE EXCEPTION 'Kun fakturerte saker kan låses opp';
  END IF;

  UPDATE public.partner_deduction_cases
  SET is_locked = false,
      unlocked_at = now(),
      unlocked_by = auth.uid()
  WHERE id = p_case_id
  RETURNING * INTO v_case;

  RETURN v_case;
END;
$$;

CREATE OR REPLACE FUNCTION public.soft_delete_partner_deduction_case(
  p_case_id UUID,
  p_deletion_comment TEXT
)
RETURNS public.partner_deduction_cases
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_case public.partner_deduction_cases%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  IF NOT public.can_unlock_partner_deduction_case() THEN
    RAISE EXCEPTION 'Kun Nico, Tommy eller Hazher kan slette saker';
  END IF;

  IF coalesce(trim(p_deletion_comment), '') = '' THEN
    RAISE EXCEPTION 'Du må skrive en kommentar ved sletting';
  END IF;

  SELECT * INTO v_case FROM public.partner_deduction_cases WHERE id = p_case_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sak ikke funnet';
  END IF;

  IF v_case.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Saken er allerede slettet';
  END IF;

  IF v_case.is_locked THEN
    RAISE EXCEPTION 'Lås opp saken før sletting';
  END IF;

  UPDATE public.partner_deduction_cases
  SET status = 'deleted',
      deleted_at = now(),
      deleted_by = auth.uid(),
      deletion_comment = trim(p_deletion_comment),
      is_locked = true,
      locked_at = coalesce(locked_at, now())
  WHERE id = p_case_id
  RETURNING * INTO v_case;

  RETURN v_case;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_partner_deduction_logiqrma(
  p_case_id UUID,
  p_logiqrma_case_number TEXT DEFAULT NULL,
  p_voucher_number TEXT DEFAULT NULL,
  p_logistics_description TEXT DEFAULT NULL
)
RETURNS public.partner_deduction_cases
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_case public.partner_deduction_cases%ROWTYPE;
  v_profile public.profiles%ROWTYPE;
  v_is_superadmin BOOLEAN := public.get_user_role() = 'superadmin'::public.user_role;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_case FROM public.partner_deduction_cases WHERE id = p_case_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sak ikke funnet';
  END IF;

  IF v_case.is_locked OR v_case.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Saken er låst og kan ikke endres';
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  IF NOT v_is_superadmin AND v_profile.company_id IS DISTINCT FROM v_case.company_id THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  UPDATE public.partner_deduction_cases
  SET
    logiqrma_case_number = nullif(trim(p_logiqrma_case_number), ''),
    voucher_number = nullif(trim(p_voucher_number), ''),
    logistics_description = nullif(trim(p_logistics_description), '')
  WHERE id = p_case_id
  RETURNING * INTO v_case;

  RETURN v_case;
END;
$$;

CREATE OR REPLACE FUNCTION public.add_partner_deduction_evidence(
  p_case_id UUID,
  p_storage_ref TEXT,
  p_storage_provider TEXT,
  p_file_name TEXT,
  p_mime_type TEXT DEFAULT NULL,
  p_media_type TEXT DEFAULT 'image',
  p_file_size_bytes BIGINT DEFAULT NULL,
  p_dropbox_path TEXT DEFAULT NULL
)
RETURNS public.partner_deduction_evidence
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_case public.partner_deduction_cases%ROWTYPE;
  v_row public.partner_deduction_evidence%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_case FROM public.partner_deduction_cases WHERE id = p_case_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sak ikke funnet';
  END IF;

  IF v_case.is_locked OR v_case.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Saken er låst og kan ikke endres';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND company_id = v_case.company_id
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  INSERT INTO public.partner_deduction_evidence (
    case_id, company_id, partner_id,
    storage_ref, storage_provider, file_name, mime_type, media_type,
    file_size_bytes, dropbox_path, owner_visible, uploaded_by
  ) VALUES (
    v_case.id, v_case.company_id, v_case.partner_id,
    p_storage_ref, coalesce(nullif(p_storage_provider, ''), 'dropbox'),
    p_file_name, p_mime_type, coalesce(nullif(p_media_type, ''), 'image'),
    p_file_size_bytes, p_dropbox_path, true, auth.uid()
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.resend_partner_deduction_notification(
  p_case_id UUID,
  p_notify_sms BOOLEAN DEFAULT true,
  p_notify_email BOOLEAN DEFAULT true
)
RETURNS public.partner_deduction_cases
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_case public.partner_deduction_cases%ROWTYPE;
  v_partner public.partners%ROWTYPE;
  v_phone TEXT;
  v_email TEXT;
  v_sms TEXT;
  v_subject TEXT;
  v_body TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  SELECT * INTO v_case FROM public.partner_deduction_cases WHERE id = p_case_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sak ikke funnet';
  END IF;

  IF v_case.is_locked OR v_case.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Saken er låst og kan ikke endres';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND company_id = v_case.company_id
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  SELECT * INTO v_partner FROM public.partners WHERE id = v_case.partner_id;
  v_phone := nullif(trim(v_partner.phone), '');
  v_email := nullif(trim(v_partner.email), '');

  v_sms := coalesce(
    nullif(trim(v_case.notification_sms_body), ''),
    format(
      'Hei %s. MAVI Logistikk — sak %s: %s. Trekk kr %s,-. %s Mvh MAVI Logistikk',
      v_partner.name, v_case.case_number, v_case.template_title,
      trim(to_char(v_case.amount_nok, '999999990')),
      v_case.short_description
    )
  );
  v_sms := replace(v_sms, '{sak}', v_case.case_number);

  v_subject := coalesce(
    nullif(trim(v_case.notification_email_subject), ''),
    format('Trekk registrert — sak %s — %s', v_case.case_number, v_partner.name)
  );
  v_subject := replace(v_subject, '{sak}', v_case.case_number);

  v_body := coalesce(
    nullif(trim(v_case.notification_email_body), ''),
    format(
      E'Hei %s,\n\nSak %s\nKategori: %s\nBeløp: kr %s,-\n\n%s\n\nMvh MAVI Logistikk AS',
      v_partner.name, v_case.case_number, v_case.template_title,
      trim(to_char(v_case.amount_nok, '999999990')),
      v_case.short_description
    )
  );
  v_body := replace(v_body, '{sak}', v_case.case_number);

  IF EXISTS (SELECT 1 FROM public.partner_deduction_evidence e WHERE e.case_id = v_case.id) THEN
    IF v_sms NOT LIKE '%portalen%' AND v_sms NOT LIKE '%Trekk%' THEN
      v_sms := v_sms || ' Bevis finnes i portalen under Trekk.';
    END IF;
    IF v_body NOT LIKE '%portalen%' THEN
      v_body := v_body || E'\n\nVedlagt bevis (bilde/video) er tilgjengelig i bil-eierportalen under «Trekk».';
    END IF;
  END IF;

  IF p_notify_sms AND v_phone IS NOT NULL THEN
    PERFORM public.queue_sms_if_allowed(
      v_case.company_id, NULL, v_phone, v_sms,
      'partner_deduction', 'partner_deduction_cases', v_case.id,
      'partner_compose', 'Bot/trekk varslet via SMS', true
    );
    UPDATE public.partner_deduction_cases
    SET sms_sent = true, notified_at = coalesce(notified_at, now()),
        status = CASE WHEN status = 'registered' THEN 'notified' ELSE status END,
        notification_sms_body = v_sms
    WHERE id = v_case.id;
  END IF;

  IF p_notify_email AND v_email IS NOT NULL THEN
    PERFORM public.queue_email_if_allowed(
      v_case.company_id, NULL, v_email, v_subject, v_body,
      'partner_deduction', 'partner_deduction_cases', v_case.id,
      'partner_compose', 'Bot/trekk varslet via e-post', true
    );
    UPDATE public.partner_deduction_cases
    SET email_sent = true, notified_at = coalesce(notified_at, now()),
        status = CASE WHEN status = 'registered' THEN 'notified' ELSE status END,
        notification_email_subject = v_subject,
        notification_email_body = v_body
    WHERE id = v_case.id;
  END IF;

  SELECT * INTO v_case FROM public.partner_deduction_cases WHERE id = p_case_id;
  RETURN v_case;
END;
$$;

DROP FUNCTION IF EXISTS public.list_partner_deduction_cases(UUID, TEXT, UUID, INT, INT);

CREATE OR REPLACE FUNCTION public.list_partner_deduction_cases(
  p_company_id UUID,
  p_status TEXT DEFAULT NULL,
  p_partner_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 200,
  p_offset INT DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  company_id UUID,
  partner_id UUID,
  partner_name TEXT,
  case_number TEXT,
  template_id TEXT,
  template_title TEXT,
  short_description TEXT,
  comment TEXT,
  amount_nok NUMERIC,
  status TEXT,
  created_by UUID,
  created_by_name TEXT,
  created_at TIMESTAMPTZ,
  notified_at TIMESTAMPTZ,
  sms_sent BOOLEAN,
  email_sent BOOLEAN,
  invoiced_at TIMESTAMPTZ,
  invoiced_by UUID,
  invoiced_by_name TEXT,
  evidence_count BIGINT,
  logiqrma_case_number TEXT,
  voucher_number TEXT,
  logistics_description TEXT,
  is_locked BOOLEAN,
  locked_at TIMESTAMPTZ,
  unlocked_at TIMESTAMPTZ,
  unlocked_by_name TEXT,
  deleted_at TIMESTAMPTZ,
  deleted_by_name TEXT,
  deletion_comment TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.id, c.company_id, c.partner_id, p.name AS partner_name,
    c.case_number, c.template_id, c.template_title, c.short_description, c.comment,
    c.amount_nok, c.status, c.created_by,
    cr.full_name AS created_by_name,
    c.created_at, c.notified_at, c.sms_sent, c.email_sent,
    c.invoiced_at, c.invoiced_by, inv.full_name AS invoiced_by_name,
    (SELECT count(*) FROM public.partner_deduction_evidence e WHERE e.case_id = c.id) AS evidence_count,
    c.logiqrma_case_number, c.voucher_number, c.logistics_description,
    c.is_locked, c.locked_at, c.unlocked_at, unl.full_name AS unlocked_by_name,
    c.deleted_at, del.full_name AS deleted_by_name, c.deletion_comment
  FROM public.partner_deduction_cases c
  JOIN public.partners p ON p.id = c.partner_id
  LEFT JOIN public.profiles cr ON cr.id = c.created_by
  LEFT JOIN public.profiles inv ON inv.id = c.invoiced_by
  LEFT JOIN public.profiles unl ON unl.id = c.unlocked_by
  LEFT JOIN public.profiles del ON del.id = c.deleted_by
  WHERE c.company_id = p_company_id
    AND EXISTS (
      SELECT 1 FROM public.profiles pr
      WHERE pr.id = auth.uid() AND pr.company_id = p_company_id
    )
    AND (p_status IS NULL OR c.status = p_status)
    AND (p_partner_id IS NULL OR c.partner_id = p_partner_id)
  ORDER BY c.created_at DESC
  LIMIT greatest(p_limit, 1)
  OFFSET greatest(p_offset, 0);
$$;

CREATE OR REPLACE FUNCTION public.get_partner_deduction_stats(p_company_id UUID)
RETURNS TABLE (
  open_count BIGINT,
  invoiced_count BIGINT,
  open_amount NUMERIC,
  invoiced_amount NUMERIC,
  evidence_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    coalesce(agg.open_count, 0),
    coalesce(agg.invoiced_count, 0),
    coalesce(agg.open_amount, 0),
    coalesce(agg.invoiced_amount, 0),
    coalesce(ev.cnt, 0)
  FROM (
    SELECT 1
    FROM public.profiles pr
    WHERE pr.id = auth.uid() AND pr.company_id = p_company_id
  ) access_check
  LEFT JOIN LATERAL (
    SELECT
      count(*) FILTER (WHERE c.status NOT IN ('invoiced', 'deleted')) AS open_count,
      count(*) FILTER (WHERE c.status = 'invoiced' AND c.deleted_at IS NULL) AS invoiced_count,
      coalesce(sum(c.amount_nok) FILTER (WHERE c.status NOT IN ('invoiced', 'deleted')), 0) AS open_amount,
      coalesce(sum(c.amount_nok) FILTER (WHERE c.status = 'invoiced' AND c.deleted_at IS NULL), 0) AS invoiced_amount
    FROM public.partner_deduction_cases c
    WHERE c.company_id = p_company_id
      AND c.deleted_at IS NULL
  ) agg ON true
  LEFT JOIN LATERAL (
    SELECT count(*)::bigint AS cnt
    FROM public.partner_deduction_evidence e
    JOIN public.partner_deduction_cases c2 ON c2.id = e.case_id
    WHERE c2.company_id = p_company_id
      AND c2.deleted_at IS NULL
  ) ev ON true;
$$;

DROP FUNCTION IF EXISTS public.list_partner_deduction_cases_portal(UUID, INT);

CREATE OR REPLACE FUNCTION public.list_partner_deduction_cases_portal(
  p_partner_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 100
)
RETURNS TABLE (
  id UUID,
  company_id UUID,
  partner_id UUID,
  partner_name TEXT,
  case_number TEXT,
  template_id TEXT,
  template_title TEXT,
  short_description TEXT,
  comment TEXT,
  amount_nok NUMERIC,
  status TEXT,
  created_at TIMESTAMPTZ,
  notified_at TIMESTAMPTZ,
  sms_sent BOOLEAN,
  email_sent BOOLEAN,
  invoiced_at TIMESTAMPTZ,
  evidence_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.id, c.company_id, c.partner_id, p.name AS partner_name,
    c.case_number, c.template_id, c.template_title, c.short_description, c.comment,
    c.amount_nok, c.status, c.created_at, c.notified_at, c.sms_sent, c.email_sent,
    c.invoiced_at,
    (SELECT count(*) FROM public.partner_deduction_evidence e WHERE e.case_id = c.id) AS evidence_count
  FROM public.partner_deduction_cases c
  JOIN public.partners p ON p.id = c.partner_id
  WHERE c.deleted_at IS NULL
    AND c.partner_id = coalesce(
      p_partner_id,
      (SELECT partner_id FROM public.profiles WHERE id = auth.uid() AND partner_id IS NOT NULL LIMIT 1)
    )
  AND EXISTS (
    SELECT 1 FROM public.profiles pr
    WHERE pr.id = auth.uid()
      AND (pr.partner_id = c.partner_id OR pr.company_id = c.company_id)
  )
  ORDER BY c.created_at DESC
  LIMIT greatest(p_limit, 1);
$$;

GRANT EXECUTE ON FUNCTION public.can_unlock_partner_deduction_case(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.unlock_partner_deduction_case(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.soft_delete_partner_deduction_case(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_partner_deduction_cases(UUID, TEXT, UUID, INT, INT) TO authenticated, service_role;
