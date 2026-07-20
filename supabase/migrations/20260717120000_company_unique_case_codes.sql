-- Unike saks-/bot-nummer per bedrift via companies.case_code.
-- Format bot:   BOT-{CODE}-{ÅR}-{SEQ}   f.eks. BOT-MAVI-2026-0001
-- Format avvik: {DOMENE}-{CODE}-{ÅR}-{SEQ}  f.eks. HMS-MAVI-2026-0001

-- ── 1. Bedriftskode ──────────────────────────────────────────────────────────

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS case_code TEXT;

COMMENT ON COLUMN public.companies.case_code IS
  'Kort unik kode brukt i bot-/avviksnummer (f.eks. MAVI → BOT-MAVI-2026-0001).';

CREATE OR REPLACE FUNCTION public.normalize_case_code(p_raw TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v TEXT;
BEGIN
  v := upper(trim(coalesce(p_raw, '')));
  v := regexp_replace(v, '[ÆÄ]', 'AE', 'g');
  v := regexp_replace(v, '[ØÖ]', 'O', 'g');
  v := regexp_replace(v, '[Å]', 'A', 'g');
  v := regexp_replace(v, '[^A-Z0-9]', '', 'g');
  IF length(v) > 8 THEN
    v := left(v, 8);
  END IF;
  RETURN NULLIF(v, '');
END;
$$;

CREATE OR REPLACE FUNCTION public.suggest_company_case_code(
  p_name TEXT,
  p_company_id UUID DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  base TEXT;
  word TEXT;
  candidate TEXT;
  n INT := 0;
BEGIN
  -- Første «ord» (bokstaver/tall) fra navnet, ellers hele normalisert.
  word := (regexp_match(upper(trim(coalesce(p_name, ''))), '[A-ZÆØÅÄÖ0-9]+'))[1];
  base := public.normalize_case_code(coalesce(word, p_name));
  IF base IS NULL OR length(base) < 2 THEN
    base := 'C' || upper(left(replace(coalesce(p_company_id::text, gen_random_uuid()::text), '-', ''), 4));
  END IF;
  IF length(base) < 3 THEN
    base := rpad(base, 3, 'X');
  END IF;

  candidate := base;
  WHILE EXISTS (
    SELECT 1 FROM public.companies c
    WHERE upper(c.case_code) = candidate
      AND (p_company_id IS NULL OR c.id IS DISTINCT FROM p_company_id)
  ) LOOP
    n := n + 1;
    candidate := left(base, 6) || n::text;
  END LOOP;

  RETURN candidate;
END;
$$;

CREATE OR REPLACE FUNCTION public.company_case_code(p_company_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code TEXT;
  v_name TEXT;
BEGIN
  IF p_company_id IS NULL THEN
    RETURN 'UKJENT';
  END IF;

  SELECT case_code, name INTO v_code, v_name
  FROM public.companies
  WHERE id = p_company_id;

  v_code := public.normalize_case_code(v_code);
  IF v_code IS NOT NULL THEN
    RETURN v_code;
  END IF;

  v_code := public.suggest_company_case_code(v_name, p_company_id);

  UPDATE public.companies
  SET case_code = v_code
  WHERE id = p_company_id
    AND (case_code IS NULL OR trim(case_code) = '');

  RETURN v_code;
END;
$$;

-- Backfill case_code for alle bedrifter
DO $$
DECLARE
  rec RECORD;
  v_code TEXT;
BEGIN
  FOR rec IN
    SELECT id, name, case_code
    FROM public.companies
    ORDER BY created_at NULLS LAST, name
  LOOP
    IF public.normalize_case_code(rec.case_code) IS NOT NULL THEN
      UPDATE public.companies
      SET case_code = public.normalize_case_code(rec.case_code)
      WHERE id = rec.id
        AND case_code IS DISTINCT FROM public.normalize_case_code(rec.case_code);
      CONTINUE;
    END IF;
    v_code := public.suggest_company_case_code(rec.name, rec.id);
    UPDATE public.companies SET case_code = v_code WHERE id = rec.id;
  END LOOP;
END;
$$;

ALTER TABLE public.companies
  ALTER COLUMN case_code SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_companies_case_code
  ON public.companies (upper(case_code));

-- Hold case_code normalisert ved insert/update
CREATE OR REPLACE FUNCTION public.companies_normalize_case_code()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.case_code IS NULL OR trim(NEW.case_code) = '' THEN
    NEW.case_code := public.suggest_company_case_code(NEW.name, NEW.id);
  ELSE
    NEW.case_code := public.normalize_case_code(NEW.case_code);
    IF NEW.case_code IS NULL THEN
      NEW.case_code := public.suggest_company_case_code(NEW.name, NEW.id);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_companies_normalize_case_code ON public.companies;
CREATE TRIGGER trg_companies_normalize_case_code
  BEFORE INSERT OR UPDATE OF case_code, name ON public.companies
  FOR EACH ROW
  EXECUTE FUNCTION public.companies_normalize_case_code();

-- ── 2. Bot-nummer: BOT-{CODE}-{ÅR}-{SEQ} ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.next_partner_deduction_case_number(p_company_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_code TEXT := public.company_case_code(p_company_id);
  v_max INT;
  v_seq INT;
  v_prefix TEXT;
BEGIN
  v_prefix := 'BOT-' || v_code || '-' || v_year || '-';

  PERFORM pg_advisory_xact_lock(
    hashtext('partner_deduction_case_num:' || p_company_id::text || ':' || v_code || ':' || v_year)
  );

  SELECT greatest(
    coalesce((
      SELECT max(
        NULLIF(regexp_replace(case_number, '^BOT-' || v_code || '-' || v_year || '-', ''), '')::INT
      )
      FROM public.partner_deduction_cases
      WHERE company_id = p_company_id
        AND case_number LIKE v_prefix || '%'
    ), 0),
    coalesce((
      -- Gamle nummer uten bedriftskode: BOT-2026-0001
      SELECT max(
        NULLIF(regexp_replace(case_number, '^BOT-' || v_year || '-', ''), '')::INT
      )
      FROM public.partner_deduction_cases
      WHERE company_id = p_company_id
        AND case_number ~ ('^BOT-' || v_year || '-[0-9]+$')
    ), 0)
  ) INTO v_max;

  v_seq := v_max + 1;
  RETURN v_prefix || lpad(v_seq::TEXT, 4, '0');
END;
$$;

-- Migrer eksisterende bot-nummer til nytt format (beholder sekvens)
UPDATE public.partner_deduction_cases c
SET
  case_number = 'BOT-' || co.case_code || '-' ||
    substring(c.case_number from 'BOT-([0-9]{4}-[0-9]+)$'),
  trace_ref = 'BOT-' || co.case_code || '-' ||
    substring(c.case_number from 'BOT-([0-9]{4}-[0-9]+)$')
FROM public.companies co
WHERE co.id = c.company_id
  AND c.case_number ~ '^BOT-[0-9]{4}-[0-9]+$'
  AND c.case_number !~ ('^BOT-' || co.case_code || '-');

-- Synk trace_ref der den henger etter
UPDATE public.partner_deduction_cases
SET trace_ref = case_number
WHERE trace_ref IS DISTINCT FROM case_number;

-- ── 3. Avvik/HMS: {DOMENE}-{CODE}-{ÅR}-{SEQ} ─────────────────────────────────

CREATE OR REPLACE FUNCTION public.next_ticket_trace_ref(
  p_company_id UUID,
  p_hms_domain TEXT DEFAULT 'hms'
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_year TEXT := to_char(now(), 'YYYY');
  v_domain TEXT := public.ticket_trace_prefix(p_hms_domain);
  v_code TEXT := public.company_case_code(p_company_id);
  v_max INT;
  v_seq INT;
  v_prefix TEXT;
BEGIN
  v_prefix := v_domain || '-' || v_code || '-' || v_year || '-';

  PERFORM pg_advisory_xact_lock(
    hashtext('ticket_trace_ref:' || p_company_id::text || ':' || v_domain || ':' || v_code || ':' || v_year)
  );

  SELECT greatest(
    coalesce((
      SELECT max(
        NULLIF(regexp_replace(trace_ref, '^' || v_domain || '-' || v_code || '-' || v_year || '-', ''), '')::INT
      )
      FROM public.tickets
      WHERE company_id = p_company_id
        AND trace_ref LIKE v_prefix || '%'
    ), 0),
    coalesce((
      -- Gamle nummer uten bedriftskode: HMS-2026-0001
      SELECT max(
        NULLIF(regexp_replace(trace_ref, '^' || v_domain || '-' || v_year || '-', ''), '')::INT
      )
      FROM public.tickets
      WHERE company_id = p_company_id
        AND trace_ref ~ ('^' || v_domain || '-' || v_year || '-[0-9]+$')
    ), 0)
  ) INTO v_max;

  v_seq := v_max + 1;
  RETURN v_prefix || lpad(v_seq::TEXT, 4, '0');
END;
$$;

-- Migrer eksisterende avviks-sporingsnummer
UPDATE public.tickets t
SET trace_ref = public.ticket_trace_prefix(t.hms_domain::text) || '-' ||
  co.case_code || '-' ||
  substring(t.trace_ref from '[A-Z]+-([0-9]{4}-[0-9]+)$')
FROM public.companies co
WHERE co.id = t.company_id
  AND t.trace_ref ~ '^[A-Z]+-[0-9]{4}-[0-9]+$'
  AND t.trace_ref !~ ('^[A-Z]+-' || co.case_code || '-');

-- Globalt unikt bot-nummer (lettere søk for superadmin på tvers av bedrifter)
CREATE UNIQUE INDEX IF NOT EXISTS uq_partner_deduction_cases_case_number_global
  ON public.partner_deduction_cases (case_number);

CREATE UNIQUE INDEX IF NOT EXISTS uq_tickets_trace_ref_global
  ON public.tickets (trace_ref)
  WHERE trace_ref IS NOT NULL AND trim(trace_ref) <> '';

GRANT EXECUTE ON FUNCTION public.normalize_case_code(TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.suggest_company_case_code(TEXT, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.company_case_code(UUID) TO authenticated, service_role;
