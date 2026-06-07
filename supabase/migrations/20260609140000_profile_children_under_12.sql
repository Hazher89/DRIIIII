-- Barn under 12 år per ansatt — brukes til sykt-barn-kvote (10 / 15 dager, Lovdata).

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS children_under_12_count integer NOT NULL DEFAULT 0;

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_children_under_12_count_check;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_children_under_12_count_check
  CHECK (children_under_12_count >= 0 AND children_under_12_count <= 12);

COMMENT ON COLUMN public.profiles.children_under_12_count IS
  'Antall egne barn under 12 år — styrer sykt-barn-kvote (10 dager / 15 ved 2+).';

CREATE OR REPLACE FUNCTION public.sykt_barn_days_limit(p_user_id uuid)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _children integer;
BEGIN
  SELECT coalesce(children_under_12_count, 0)
  INTO _children
  FROM public.profiles
  WHERE id = p_user_id;

  IF _children >= 2 THEN
    RETURN 15;
  END IF;
  RETURN 10;
END;
$$;

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
  _limit integer;
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
  _limit := public.sykt_barn_days_limit(new.user_id);

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

GRANT EXECUTE ON FUNCTION public.sykt_barn_days_limit(uuid) TO authenticated;
