-- Ferie: virkedager (ferieloven) og korrekt kvotefordeling over årsskifte.

ALTER TABLE public.absences
  ADD COLUMN IF NOT EXISTS vacation_day_count INTEGER;

-- ── Norske virkedager (speiler lib/core/utils/business_days.dart) ───────────

CREATE OR REPLACE FUNCTION public.easter_sunday(p_year integer)
RETURNS date
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  a integer;
  b integer;
  c integer;
  d integer;
  e integer;
  f integer;
  g integer;
  h integer;
  i integer;
  k integer;
  l integer;
  m integer;
  n_month integer;
  n_day integer;
BEGIN
  a := p_year % 19;
  b := p_year / 100;
  c := p_year % 100;
  d := b / 4;
  e := b % 4;
  f := (b + 8) / 25;
  g := (b - f + 1) / 3;
  h := (19 * a + b - d - g + 15) % 30;
  i := c / 4;
  k := c % 4;
  l := (32 + 2 * e + 2 * i - h - k) % 7;
  m := (a + 11 * h + 22 * l) / 451;
  n_month := (h + l - 7 * m + 114) / 31;
  n_day := ((h + l - 7 * m + 114) % 31) + 1;
  RETURN make_date(p_year, n_month, n_day);
END;
$$;

CREATE OR REPLACE FUNCTION public.is_norwegian_public_holiday(p_date date)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  y integer := extract(year from p_date)::int;
  easter date := public.easter_sunday(y);
BEGIN
  IF extract(month from p_date) = 1 AND extract(day from p_date) = 1 THEN RETURN true; END IF;
  IF extract(month from p_date) = 5 AND extract(day from p_date) = 1 THEN RETURN true; END IF;
  IF extract(month from p_date) = 5 AND extract(day from p_date) = 17 THEN RETURN true; END IF;
  IF extract(month from p_date) = 12 AND extract(day from p_date) = 25 THEN RETURN true; END IF;
  IF extract(month from p_date) = 12 AND extract(day from p_date) = 26 THEN RETURN true; END IF;

  IF p_date = easter - 2 THEN RETURN true; END IF; -- langfredag
  IF p_date = easter + 1 THEN RETURN true; END IF; -- 2. påskedag
  IF p_date = easter + 39 THEN RETURN true; END IF; -- kristi himmelfartsdag
  IF p_date = easter + 50 THEN RETURN true; END IF; -- 2. pinsedag

  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_norwegian_business_day(p_date date)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  dow integer := extract(dow from p_date)::int; -- 0=søn, 6=lør
BEGIN
  IF dow = 0 OR dow = 6 THEN
    RETURN false;
  END IF;
  RETURN NOT public.is_norwegian_public_holiday(p_date);
END;
$$;

CREATE OR REPLACE FUNCTION public.count_ferie_business_days_in_year(
  p_start date,
  p_end date,
  p_year integer
)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  year_start date := make_date(p_year, 1, 1);
  year_end date := make_date(p_year, 12, 31);
  from_d date := greatest(p_start, year_start);
  to_d date := least(p_end, year_end);
  d date;
  cnt integer := 0;
BEGIN
  IF from_d > to_d THEN
    RETURN 0;
  END IF;

  d := from_d;
  WHILE d <= to_d LOOP
    IF public.is_norwegian_business_day(d) THEN
      cnt := cnt + 1;
    END IF;
    d := d + 1;
  END LOOP;

  RETURN cnt;
END;
$$;

CREATE OR REPLACE FUNCTION public.count_ferie_business_days(p_start date, p_end date)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  y integer;
  y_end integer;
  total integer := 0;
BEGIN
  IF p_end < p_start THEN
    RETURN 0;
  END IF;

  y := extract(year from p_start)::int;
  y_end := extract(year from p_end)::int;

  WHILE y <= y_end LOOP
    total := total + public.count_ferie_business_days_in_year(p_start, p_end, y);
    y := y + 1;
  END LOOP;

  RETURN total;
END;
$$;

-- ── Sett vacation_day_count før lagring ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_absence_vacation_day_count()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF new.type = 'ferie' THEN
    new.vacation_day_count := public.count_ferie_business_days(new.start_date, new.end_date);
  ELSE
    new.vacation_day_count := NULL;
  END IF;
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS set_vacation_day_count ON public.absences;
CREATE TRIGGER set_vacation_day_count
  BEFORE INSERT OR UPDATE OF type, start_date, end_date ON public.absences
  FOR EACH ROW
  EXECUTE FUNCTION public.set_absence_vacation_day_count();

-- ── Kvote per år (ferie) ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.apply_ferie_quota_delta(
  p_user_id uuid,
  p_company_id uuid,
  p_start date,
  p_end date,
  p_delta integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  y integer;
  y_end integer;
  days_in_year integer;
BEGIN
  IF p_end < p_start OR p_delta = 0 THEN
    RETURN;
  END IF;

  y := extract(year from p_start)::int;
  y_end := extract(year from p_end)::int;

  WHILE y <= y_end LOOP
    days_in_year := public.count_ferie_business_days_in_year(p_start, p_end, y);
    IF days_in_year > 0 THEN
      INSERT INTO public.absence_quotas (user_id, company_id, year, vacation_days_total)
      VALUES (p_user_id, p_company_id, y, 25)
      ON CONFLICT (user_id, year) DO NOTHING;

      UPDATE public.absence_quotas
      SET vacation_days_used = greatest(0, vacation_days_used + (days_in_year * p_delta)),
          updated_at = now()
      WHERE user_id = p_user_id AND year = y;
    END IF;
    y := y + 1;
  END LOOP;
END;
$$;

-- ── Valider ferie mot kvote per år ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.validate_ferie_quota()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _quota public.absence_quotas%rowtype;
  _remaining integer;
  _year integer;
  _year_end integer;
  _days_in_year integer;
  _total_days integer;
BEGIN
  IF new.type != 'ferie' THEN
    RETURN new;
  END IF;

  IF new.status != 'godkjent' THEN
    RETURN new;
  END IF;

  _total_days := public.count_ferie_business_days(new.start_date, new.end_date);
  IF _total_days < 1 THEN
    RAISE EXCEPTION 'Ferieperioden inneholder ingen virkedager';
  END IF;

  _year := extract(year from new.start_date)::int;
  _year_end := extract(year from new.end_date)::int;

  WHILE _year <= _year_end LOOP
    _days_in_year := public.count_ferie_business_days_in_year(
      new.start_date, new.end_date, _year
    );
    IF _days_in_year > 0 THEN
      SELECT * INTO _quota FROM public.absence_quotas
      WHERE user_id = new.user_id AND year = _year;

      IF _quota IS NULL THEN
        RAISE EXCEPTION 'Ingen feriekvote for % — kontakt administrator', _year;
      END IF;

      _remaining := (_quota.vacation_days_total + _quota.vacation_days_carried_over)
        - _quota.vacation_days_used;

      IF _days_in_year > _remaining THEN
        RAISE EXCEPTION 'Ikke nok feriedager igjen for % (% igjen, perioden krever %)',
          _year, _remaining, _days_in_year;
      END IF;
    END IF;
    _year := _year + 1;
  END LOOP;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS validate_ferie_quota_trigger ON public.absences;
CREATE TRIGGER validate_ferie_quota_trigger
  BEFORE INSERT OR UPDATE ON public.absences
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_ferie_quota();

-- ── Oppdater kvote ved godkjenning (ferie fordelt per år) ─────────────────────

CREATE OR REPLACE FUNCTION public.update_absence_quota()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF new.status = 'godkjent' AND (
    tg_op = 'INSERT'
    OR old.status IS DISTINCT FROM 'godkjent'
  ) THEN
    IF new.type = 'egenmelding' THEN
      UPDATE public.absence_quotas
      SET egenmelding_days_used = egenmelding_days_used + new.total_days,
          egenmelding_periods_used = egenmelding_periods_used + 1
      WHERE user_id = new.user_id AND year = new.quota_year;
    ELSIF new.type = 'ferie' THEN
      PERFORM public.apply_ferie_quota_delta(
        new.user_id, new.company_id, new.start_date, new.end_date, 1
      );
    ELSIF new.type = 'sykt_barn' THEN
      UPDATE public.absence_quotas
      SET sykt_barn_days_used = sykt_barn_days_used + new.total_days
      WHERE user_id = new.user_id AND year = new.quota_year;
    END IF;
  END IF;

  IF tg_op = 'UPDATE'
    AND old.status = 'godkjent'
    AND new.status IS DISTINCT FROM 'godkjent' THEN
    IF old.type = 'egenmelding' THEN
      UPDATE public.absence_quotas
      SET egenmelding_days_used = greatest(0, egenmelding_days_used - old.total_days),
          egenmelding_periods_used = greatest(0, egenmelding_periods_used - 1)
      WHERE user_id = old.user_id AND year = old.quota_year;
    ELSIF old.type = 'ferie' THEN
      PERFORM public.apply_ferie_quota_delta(
        old.user_id, old.company_id, old.start_date, old.end_date, -1
      );
    ELSIF old.type = 'sykt_barn' THEN
      UPDATE public.absence_quotas
      SET sykt_barn_days_used = greatest(0, sykt_barn_days_used - old.total_days)
      WHERE user_id = old.user_id AND year = old.quota_year;
    END IF;
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS update_quota_on_approval ON public.absences;
CREATE TRIGGER update_quota_on_approval
  AFTER INSERT OR UPDATE ON public.absences
  FOR EACH ROW
  EXECUTE FUNCTION public.update_absence_quota();

-- ── Rekalkuler eksisterende feriekvoter fra godkjente perioder ────────────────

UPDATE public.absences
SET vacation_day_count = public.count_ferie_business_days(start_date, end_date)
WHERE type = 'ferie';

UPDATE public.absence_quotas
SET vacation_days_used = 0,
    updated_at = now();

DO $$
DECLARE
  rec record;
BEGIN
  FOR rec IN
    SELECT user_id, company_id, start_date, end_date
    FROM public.absences
    WHERE type = 'ferie' AND status = 'godkjent'
    ORDER BY created_at
  LOOP
    PERFORM public.apply_ferie_quota_delta(
      rec.user_id, rec.company_id, rec.start_date, rec.end_date, 1
    );
  END LOOP;
END;
$$;
