-- Bot/trekk: unike saksnummer per samarbeidsbedrift (partner), ikke hub-selskap.
-- Format: BOT-{PARTNERKODE}-{ÅR}-{SEQ}  f.eks. BOT-ALNABLSI-2026-0001

ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS case_code TEXT;

COMMENT ON COLUMN public.partners.case_code IS
  'Unik kode for bot-/trekk-saker for denne samarbeidsbedriften (BOT-{kode}-{år}-{seq}).';

CREATE OR REPLACE FUNCTION public.suggest_partner_case_code(
  p_name TEXT,
  p_trade_name TEXT DEFAULT NULL,
  p_partner_id UUID DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_label TEXT;
  word TEXT;
  base TEXT;
  candidate TEXT;
  n INT := 0;
BEGIN
  v_label := coalesce(nullif(trim(p_trade_name), ''), nullif(trim(p_name), ''));
  word := (regexp_match(upper(coalesce(v_label, '')), '[A-ZÆØÅÄÖ0-9]+'))[1];
  base := public.normalize_case_code(coalesce(word, v_label));
  IF base IS NULL OR length(base) < 2 THEN
    base := 'P' || upper(left(replace(coalesce(p_partner_id::text, gen_random_uuid()::text), '-', ''), 5));
  END IF;
  IF length(base) < 3 THEN
    base := rpad(base, 3, 'X');
  END IF;

  candidate := base;
  WHILE EXISTS (
    SELECT 1 FROM public.partners p
    WHERE upper(p.case_code) = candidate
      AND (p_partner_id IS NULL OR p.id IS DISTINCT FROM p_partner_id)
  ) LOOP
    n := n + 1;
    candidate := left(base, 6) || n::text;
  END LOOP;

  RETURN candidate;
END;
$$;

CREATE OR REPLACE FUNCTION public.partner_case_code(p_partner_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code TEXT;
  v_name TEXT;
  v_trade TEXT;
BEGIN
  IF p_partner_id IS NULL THEN
    RETURN 'UKJENT';
  END IF;

  SELECT case_code, name, trade_name
  INTO v_code, v_name, v_trade
  FROM public.partners
  WHERE id = p_partner_id;

  v_code := public.normalize_case_code(v_code);
  IF v_code IS NOT NULL THEN
    RETURN v_code;
  END IF;

  v_code := public.suggest_partner_case_code(v_name, v_trade, p_partner_id);

  UPDATE public.partners
  SET case_code = v_code
  WHERE id = p_partner_id
    AND (case_code IS NULL OR trim(case_code) = '');

  RETURN v_code;
END;
$$;

-- Backfill alle samarbeidsbedrifter
DO $$
DECLARE
  rec RECORD;
  v_code TEXT;
BEGIN
  FOR rec IN
    SELECT id, name, trade_name, case_code
    FROM public.partners
    ORDER BY created_at NULLS LAST, name
  LOOP
    IF public.normalize_case_code(rec.case_code) IS NOT NULL THEN
      UPDATE public.partners
      SET case_code = public.normalize_case_code(rec.case_code)
      WHERE id = rec.id
        AND case_code IS DISTINCT FROM public.normalize_case_code(rec.case_code);
      CONTINUE;
    END IF;
    v_code := public.suggest_partner_case_code(rec.name, rec.trade_name, rec.id);
    UPDATE public.partners SET case_code = v_code WHERE id = rec.id;
  END LOOP;
END;
$$;

ALTER TABLE public.partners
  ALTER COLUMN case_code SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_partners_case_code
  ON public.partners (upper(case_code));

CREATE OR REPLACE FUNCTION public.partners_normalize_case_code()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.case_code IS NULL OR trim(NEW.case_code) = '' THEN
    NEW.case_code := public.suggest_partner_case_code(NEW.name, NEW.trade_name, NEW.id);
  ELSE
    NEW.case_code := public.normalize_case_code(NEW.case_code);
    IF NEW.case_code IS NULL THEN
      NEW.case_code := public.suggest_partner_case_code(NEW.name, NEW.trade_name, NEW.id);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_partners_normalize_case_code ON public.partners;
CREATE TRIGGER trg_partners_normalize_case_code
  BEFORE INSERT OR UPDATE OF case_code, name, trade_name ON public.partners
  FOR EACH ROW
  EXECUTE FUNCTION public.partners_normalize_case_code();

-- Bot-nummer per partner (samarbeidsbedrift)
CREATE OR REPLACE FUNCTION public.next_partner_deduction_case_number(
  p_company_id UUID,
  p_partner_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_code TEXT := public.partner_case_code(p_partner_id);
  v_max INT;
  v_seq INT;
  v_prefix TEXT;
BEGIN
  IF p_partner_id IS NULL THEN
    RAISE EXCEPTION 'partner_id required for case number';
  END IF;

  v_prefix := 'BOT-' || v_code || '-' || v_year || '-';

  PERFORM pg_advisory_xact_lock(
    hashtext('partner_deduction_case_num:' || p_partner_id::text || ':' || v_code || ':' || v_year)
  );

  SELECT greatest(
    coalesce((
      SELECT max(
        NULLIF(regexp_replace(case_number, '^' || v_prefix, ''), '')::INT
      )
      FROM public.partner_deduction_cases
      WHERE partner_id = p_partner_id
        AND case_number LIKE v_prefix || '%'
    ), 0),
    coalesce((
      -- Legacy uten partnerkode: BOT-2026-0001
      SELECT max(
        NULLIF(regexp_replace(case_number, '^BOT-' || v_year || '-', ''), '')::INT
      )
      FROM public.partner_deduction_cases
      WHERE partner_id = p_partner_id
        AND case_number ~ ('^BOT-' || v_year || '-[0-9]+$')
    ), 0),
    coalesce((
      -- Legacy med hub-kode (f.eks. BOT-MAVI-2026-0003) — tell sekvens for denne partneren
      SELECT max(
        NULLIF(regexp_replace(case_number, '^BOT-[A-Z0-9]+-' || v_year || '-', ''), '')::INT
      )
      FROM public.partner_deduction_cases
      WHERE partner_id = p_partner_id
        AND case_number ~ ('^BOT-[A-Z0-9]+-' || v_year || '-[0-9]+$')
    ), 0)
  ) INTO v_max;

  v_seq := v_max + 1;
  RETURN v_prefix || lpad(v_seq::TEXT, 4, '0');
END;
$$;

-- Migrer eksisterende saker til partner-spesifikke nummer (per partner + år)
WITH renumbered AS (
  SELECT
    c.id,
    p.case_code,
    to_char(c.created_at AT TIME ZONE 'UTC', 'YYYY') AS yr,
    row_number() OVER (
      PARTITION BY c.partner_id, to_char(c.created_at AT TIME ZONE 'UTC', 'YYYY')
      ORDER BY c.created_at, c.id
    ) AS seq
  FROM public.partner_deduction_cases c
  JOIN public.partners p ON p.id = c.partner_id
)
UPDATE public.partner_deduction_cases c
SET
  case_number = 'BOT-' || r.case_code || '-' || r.yr || '-' || lpad(r.seq::text, 4, '0'),
  trace_ref = 'BOT-' || r.case_code || '-' || r.yr || '-' || lpad(r.seq::text, 4, '0')
FROM renumbered r
WHERE c.id = r.id
  AND c.case_number IS DISTINCT FROM (
    'BOT-' || r.case_code || '-' || r.yr || '-' || lpad(r.seq::text, 4, '0')
  );

UPDATE public.partner_deduction_cases
SET trace_ref = case_number
WHERE trace_ref IS DISTINCT FROM case_number;

-- Oppdater create RPC
CREATE OR REPLACE FUNCTION public.create_partner_deduction_case(
  p_company_id UUID,
  p_partner_id UUID,
  p_template_id TEXT,
  p_template_title TEXT,
  p_short_description TEXT,
  p_comment TEXT DEFAULT NULL,
  p_amount_nok NUMERIC DEFAULT 500,
  p_notify_sms BOOLEAN DEFAULT false,
  p_notify_email BOOLEAN DEFAULT false,
  p_sms_body TEXT DEFAULT NULL,
  p_email_subject TEXT DEFAULT NULL,
  p_email_body TEXT DEFAULT NULL,
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
  v_row public.partner_deduction_cases%ROWTYPE;
  v_case_number TEXT;
  v_partner public.partners%ROWTYPE;
  v_phone TEXT;
  v_email TEXT;
  v_amount NUMERIC(12, 2);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Ikke innlogget';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND company_id = p_company_id
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang til bedrift';
  END IF;

  SELECT * INTO v_partner FROM public.partners
  WHERE id = p_partner_id AND company_id = p_company_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Partner ikke funnet';
  END IF;

  v_amount := coalesce(p_amount_nok, 500);
  IF v_amount < 0 THEN
    RAISE EXCEPTION 'Beløp kan ikke være negativt';
  END IF;

  v_case_number := public.next_partner_deduction_case_number(p_company_id, p_partner_id);

  INSERT INTO public.partner_deduction_cases (
    company_id, partner_id, case_number, trace_ref,
    template_id, template_title, short_description, comment,
    amount_nok, status, created_by,
    notification_sms_body, notification_email_subject, notification_email_body,
    logiqrma_case_number, voucher_number, logistics_description
  ) VALUES (
    p_company_id, p_partner_id, v_case_number, v_case_number,
    p_template_id, p_template_title, p_short_description, nullif(trim(p_comment), ''),
    v_amount, 'registered', auth.uid(),
    p_sms_body, p_email_subject, p_email_body,
    nullif(trim(p_logiqrma_case_number), ''),
    nullif(trim(p_voucher_number), ''),
    nullif(trim(p_logistics_description), '')
  )
  RETURNING * INTO v_row;

  v_phone := nullif(trim(v_partner.phone), '');
  v_email := nullif(trim(v_partner.email), '');

  IF p_notify_sms AND v_phone IS NOT NULL AND coalesce(p_sms_body, '') <> '' THEN
    PERFORM public.queue_sms_if_allowed(
      p_company_id, NULL, v_phone, replace(p_sms_body, '{sak}', v_case_number),
      'partner_deduction', 'partner_deduction_cases', v_row.id,
      'partner_compose', 'Bot/trekk varslet via SMS', true
    );
    UPDATE public.partner_deduction_cases
    SET sms_sent = true, notified_at = coalesce(notified_at, now()),
        status = CASE WHEN status = 'registered' THEN 'notified' ELSE status END
    WHERE id = v_row.id
    RETURNING * INTO v_row;
  END IF;

  IF p_notify_email AND v_email IS NOT NULL
     AND coalesce(p_email_subject, '') <> ''
     AND coalesce(p_email_body, '') <> '' THEN
    PERFORM public.queue_email_if_allowed(
      p_company_id, NULL, v_email,
      replace(p_email_subject, '{sak}', v_case_number),
      replace(p_email_body, '{sak}', v_case_number),
      'partner_deduction', 'partner_deduction_cases', v_row.id,
      'partner_compose', 'Bot/trekk varslet via e-post', true
    );
    UPDATE public.partner_deduction_cases
    SET email_sent = true, notified_at = coalesce(notified_at, now()),
        status = CASE WHEN status = 'registered' THEN 'notified' ELSE status END
    WHERE id = v_row.id
    RETURNING * INTO v_row;
  END IF;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.suggest_partner_case_code(TEXT, TEXT, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.partner_case_code(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.next_partner_deduction_case_number(UUID, UUID) TO authenticated, service_role;
