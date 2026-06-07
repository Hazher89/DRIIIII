-- Egenmelding og sykt barn: 12-måneders periode fra ansettelsesdato (som legacy-systemet).
-- Ferie forblir per kalenderår med virkedager.

CREATE OR REPLACE FUNCTION public.get_leave_period_bounds(
  p_user_id uuid,
  p_reference date DEFAULT current_date
)
RETURNS TABLE(period_start date, period_end date)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _hire date;
  _ref date := coalesce(p_reference, current_date);
  _start date;
  _end date;
  _y integer;
  _m integer;
  _d integer;
  _last_day integer;
BEGIN
  SELECT hire_date INTO _hire FROM public.profiles WHERE id = p_user_id;

  IF _hire IS NULL THEN
    period_start := date_trunc('year', _ref)::date;
    period_end := (date_trunc('year', _ref) + interval '1 year' - interval '1 day')::date;
    RETURN NEXT;
    RETURN;
  END IF;

  _m := extract(month from _hire)::int;
  _d := extract(day from _hire)::int;
  _y := extract(year from _ref)::int;
  _last_day := extract(day from (date_trunc('month', make_date(_y, _m, 1)) + interval '1 month - 1 day'))::int;
  _start := make_date(_y, _m, least(_d, _last_day));

  IF _start > _ref THEN
    _y := _y - 1;
    _last_day := extract(day from (date_trunc('month', make_date(_y, _m, 1)) + interval '1 month - 1 day'))::int;
    _start := make_date(_y, _m, least(_d, _last_day));
  END IF;

  _y := extract(year from _start)::int + 1;
  _last_day := extract(day from (date_trunc('month', make_date(_y, _m, 1)) + interval '1 month - 1 day'))::int;
  _end := make_date(_y, _m, least(_d, _last_day));

  period_start := _start;
  period_end := _end;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_egenmelding()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _company public.companies%rowtype;
  _days integer;
  _p_start date;
  _p_end date;
  _used_days integer;
  _used_periods integer;
BEGIN
  IF new.type != 'egenmelding' THEN
    RETURN new;
  END IF;

  IF tg_op = 'UPDATE'
    AND old.status IS NOT DISTINCT FROM 'godkjent'
    AND new.status IS NOT DISTINCT FROM 'godkjent' THEN
    RETURN new;
  END IF;

  IF tg_op = 'UPDATE' AND new.status IS DISTINCT FROM 'godkjent' THEN
    RETURN new;
  END IF;

  _days := new.end_date - new.start_date + 1;
  SELECT * INTO _company FROM public.companies WHERE id = new.company_id;

  IF _days > _company.egenmelding_consecutive_max THEN
    RAISE EXCEPTION 'Egenmelding kan ikke overstige % sammenhengende dager',
      _company.egenmelding_consecutive_max;
  END IF;

  SELECT b.period_start, b.period_end
  INTO _p_start, _p_end
  FROM public.get_leave_period_bounds(new.user_id, new.start_date) b;

  SELECT
    coalesce(sum(total_days), 0),
    count(*)::int
  INTO _used_days, _used_periods
  FROM public.absences
  WHERE user_id = new.user_id
    AND type = 'egenmelding'
    AND status = 'godkjent'
    AND start_date >= _p_start
    AND start_date <= _p_end
    AND (tg_op = 'INSERT' OR id IS DISTINCT FROM new.id);

  IF tg_op = 'INSERT' OR new.status = 'godkjent' THEN
    _used_days := _used_days + _days;
    _used_periods := _used_periods + 1;
  END IF;

  IF _used_periods > 4 THEN
    RAISE EXCEPTION 'Maks 4 egenmeldingsperioder i perioden %–% er brukt',
      to_char(_p_start, 'DD.MM.YYYY'), to_char(_p_end, 'DD.MM.YYYY');
  END IF;

  IF _used_days > _company.egenmelding_days_per_year THEN
    RAISE EXCEPTION 'Egenmeldingskvoten i perioden %–% er brukt opp (% av % dager)',
      to_char(_p_start, 'DD.MM.YYYY'), to_char(_p_end, 'DD.MM.YYYY'),
      _used_days - _days, _company.egenmelding_days_per_year;
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS validate_egenmelding_trigger ON public.absences;
CREATE TRIGGER validate_egenmelding_trigger
  BEFORE INSERT OR UPDATE ON public.absences
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_egenmelding();

CREATE OR REPLACE FUNCTION public.validate_sykt_barn()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _days integer;
  _p_start date;
  _p_end date;
  _used_days integer;
  _limit integer := 10;
BEGIN
  IF new.type != 'sykt_barn' THEN
    RETURN new;
  END IF;

  IF tg_op = 'UPDATE'
    AND old.status IS NOT DISTINCT FROM 'godkjent'
    AND new.status IS NOT DISTINCT FROM 'godkjent' THEN
    RETURN new;
  END IF;

  IF tg_op = 'UPDATE' AND new.status IS DISTINCT FROM 'godkjent' THEN
    RETURN new;
  END IF;

  _days := new.end_date - new.start_date + 1;

  SELECT b.period_start, b.period_end
  INTO _p_start, _p_end
  FROM public.get_leave_period_bounds(new.user_id, new.start_date) b;

  SELECT coalesce(sum(total_days), 0)
  INTO _used_days
  FROM public.absences
  WHERE user_id = new.user_id
    AND type = 'sykt_barn'
    AND status = 'godkjent'
    AND start_date >= _p_start
    AND start_date <= _p_end
    AND (tg_op = 'INSERT' OR id IS DISTINCT FROM new.id);

  IF tg_op = 'INSERT' OR new.status = 'godkjent' THEN
    _used_days := _used_days + _days;
  END IF;

  IF _used_days > _limit THEN
    RAISE EXCEPTION 'Sykt-barn-kvoten i perioden %–% er overskredet (% av % dager)',
      to_char(_p_start, 'DD.MM.YYYY'), to_char(_p_end, 'DD.MM.YYYY'),
      _used_days - _days, _limit;
  END IF;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS validate_sykt_barn_trigger ON public.absences;
CREATE TRIGGER validate_sykt_barn_trigger
  BEFORE INSERT OR UPDATE ON public.absences
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_sykt_barn();

-- Kun ferie oppdaterer absence_quotas; egenmelding/sykt barn beregnes fra perioden.
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
    IF new.type = 'ferie' THEN
      PERFORM public.apply_ferie_quota_delta(
        new.user_id, new.company_id, new.start_date, new.end_date, 1
      );
    END IF;
  END IF;

  IF tg_op = 'UPDATE'
    AND old.status = 'godkjent'
    AND new.status IS DISTINCT FROM 'godkjent' THEN
    IF old.type = 'ferie' THEN
      PERFORM public.apply_ferie_quota_delta(
        old.user_id, old.company_id, old.start_date, old.end_date, -1
      );
    END IF;
  END IF;

  RETURN new;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_leave_period_bounds(uuid, date) TO authenticated;
