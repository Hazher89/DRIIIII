-- Digitalt servicehefte per truck/maskin + SMS-påminnelser (krever sms_outbox_sveve.sql)
-- Kjør etter equipment_smart_system.sql

-- Utvid loggtyper: vask, lagring
ALTER TABLE public.equipment_maintenance_logs
  DROP CONSTRAINT IF EXISTS equipment_maintenance_logs_maintenance_type_check;

ALTER TABLE public.equipment_maintenance_logs
  ADD CONSTRAINT equipment_maintenance_logs_maintenance_type_check
  CHECK (maintenance_type IN (
    'service', 'water_fill', 'inspection', 'repair', 'wash', 'storage',
    'purchase_note', 'other'
  ));

-- Digitalt servicehefte (én per truck/maskin/kjøretøy)
CREATE TABLE IF NOT EXISTS public.equipment_service_books (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  equipment_id UUID NOT NULL UNIQUE REFERENCES public.equipment(id) ON DELETE CASCADE,
  book_number TEXT NOT NULL DEFAULT '',
  title TEXT NOT NULL,
  opened_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  is_active BOOLEAN NOT NULL DEFAULT true
);

CREATE INDEX IF NOT EXISTS idx_eq_book_company ON public.equipment_service_books(company_id);

-- Planlagte frister med SMS til valgte ansatte
CREATE TABLE IF NOT EXISTS public.equipment_service_reminders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  equipment_id UUID NOT NULL REFERENCES public.equipment(id) ON DELETE CASCADE,
  service_book_id UUID REFERENCES public.equipment_service_books(id) ON DELETE CASCADE,
  reminder_type TEXT NOT NULL
    CHECK (reminder_type IN ('service', 'water_fill', 'inspection')),
  due_date DATE NOT NULL,
  notify_user_ids UUID[] NOT NULL DEFAULT '{}',
  notify_days_before INT NOT NULL DEFAULT 7,
  sms_sent_at TIMESTAMPTZ,
  notes TEXT,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  cancelled_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_eq_reminder_due ON public.equipment_service_reminders(due_date)
  WHERE cancelled_at IS NULL AND sms_sent_at IS NULL;

ALTER TABLE public.equipment_service_books ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.equipment_service_reminders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "eq_book_company" ON public.equipment_service_books;
CREATE POLICY "eq_book_company" ON public.equipment_service_books
  FOR ALL
  USING (company_id = public.current_user_company_id())
  WITH CHECK (company_id = public.current_user_company_id());

DROP POLICY IF EXISTS "eq_reminder_company" ON public.equipment_service_reminders;
CREATE POLICY "eq_reminder_company" ON public.equipment_service_reminders
  FOR ALL
  USING (company_id = public.current_user_company_id())
  WITH CHECK (company_id = public.current_user_company_id());

-- Auto-opprett servicehefte ved ny truck/maskin/kjøretøy
CREATE OR REPLACE FUNCTION public.equipment_auto_service_book()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  num TEXT;
BEGIN
  IF NEW.category IN ('truck', 'vehicle', 'machine') THEN
    num := 'SH-' || to_char(now(), 'YYMMDD') || '-' || left(replace(NEW.id::text, '-', ''), 6);
    INSERT INTO public.equipment_service_books (
      company_id, equipment_id, book_number, title, created_by
    ) VALUES (
      NEW.company_id,
      NEW.id,
      num,
      'Servicehefte – ' || NEW.name,
      NEW.registered_by
    )
    ON CONFLICT (equipment_id) DO NOTHING;

    -- Første linje i heftet
    INSERT INTO public.equipment_maintenance_logs (
      company_id, equipment_id, maintenance_type, performed_at, performed_by, notes
    ) VALUES (
      NEW.company_id,
      NEW.id,
      'other',
      now(),
      NEW.registered_by,
      'Servicehefte opprettet automatisk ved registrering av ' || NEW.name
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_equipment_auto_service_book ON public.equipment;
CREATE TRIGGER trg_equipment_auto_service_book
  AFTER INSERT ON public.equipment
  FOR EACH ROW EXECUTE FUNCTION public.equipment_auto_service_book();

-- Sikre servicehefte (kan kalles fra app)
CREATE OR REPLACE FUNCTION public.ensure_equipment_service_book(p_equipment_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  eq public.equipment%ROWTYPE;
  book_id UUID;
  num TEXT;
BEGIN
  SELECT * INTO eq FROM public.equipment WHERE id = p_equipment_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Utstyr ikke funnet';
  END IF;
  IF eq.company_id IS DISTINCT FROM public.current_user_company_id() THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  SELECT id INTO book_id FROM public.equipment_service_books WHERE equipment_id = p_equipment_id;
  IF book_id IS NOT NULL THEN
    RETURN book_id;
  END IF;

  num := 'SH-' || to_char(now(), 'YYMMDD') || '-' || left(replace(p_equipment_id::text, '-', ''), 6);
  INSERT INTO public.equipment_service_books (
    company_id, equipment_id, book_number, title, created_by
  ) VALUES (
    eq.company_id, p_equipment_id, num, 'Servicehefte – ' || eq.name, auth.uid()
  )
  RETURNING id INTO book_id;

  RETURN book_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_equipment_service_book(UUID) TO authenticated;

-- Planlegg neste service/vann + SMS-varsling
CREATE OR REPLACE FUNCTION public.schedule_equipment_reminder(
  p_equipment_id UUID,
  p_reminder_type TEXT,
  p_due_date DATE,
  p_notify_user_ids UUID[],
  p_notify_days_before INT DEFAULT 7,
  p_notes TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  eq public.equipment%ROWTYPE;
  book_id UUID;
  rem_id UUID;
BEGIN
  SELECT * INTO eq FROM public.equipment WHERE id = p_equipment_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Utstyr ikke funnet'; END IF;
  IF eq.company_id IS DISTINCT FROM public.current_user_company_id() THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  book_id := public.ensure_equipment_service_book(p_equipment_id);

  -- Avbryt gamle åpne påminnelser av samme type
  UPDATE public.equipment_service_reminders
  SET cancelled_at = now()
  WHERE equipment_id = p_equipment_id
    AND reminder_type = p_reminder_type
    AND cancelled_at IS NULL
    AND sms_sent_at IS NULL;

  INSERT INTO public.equipment_service_reminders (
    company_id, equipment_id, service_book_id, reminder_type,
    due_date, notify_user_ids, notify_days_before, notes, created_by
  ) VALUES (
    eq.company_id, p_equipment_id, book_id, p_reminder_type,
    p_due_date, COALESCE(p_notify_user_ids, '{}'), p_notify_days_before, p_notes, auth.uid()
  )
  RETURNING id INTO rem_id;

  IF p_reminder_type = 'service' THEN
    UPDATE public.equipment SET next_service = p_due_date WHERE id = p_equipment_id;
  ELSIF p_reminder_type = 'water_fill' THEN
    UPDATE public.equipment SET next_water_check = p_due_date WHERE id = p_equipment_id;
  ELSIF p_reminder_type = 'inspection' THEN
    UPDATE public.equipment SET next_inspection = p_due_date WHERE id = p_equipment_id;
  END IF;

  RETURN rem_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.schedule_equipment_reminder(UUID, TEXT, DATE, UUID[], INT, TEXT) TO authenticated;

-- Send SMS-påminnelser (cron: daglig kl 07:00)
CREATE OR REPLACE FUNCTION public.process_equipment_service_sms_reminders()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  u RECORD;
  eq public.equipment%ROWTYPE;
  msg TEXT;
  sent_count INT := 0;
  notify_day DATE;
BEGIN
  FOR r IN
    SELECT * FROM public.equipment_service_reminders
    WHERE cancelled_at IS NULL
      AND sms_sent_at IS NULL
      AND array_length(notify_user_ids, 1) > 0
  LOOP
    IF CURRENT_DATE < (r.due_date - r.notify_days_before) THEN
      CONTINUE;
    END IF;

    SELECT * INTO eq FROM public.equipment WHERE id = r.equipment_id;

    msg := 'DriftPro: ' || coalesce(eq.name, 'Truck') ||
      ' – ' || CASE r.reminder_type
        WHEN 'water_fill' THEN 'påminnelse vann/batteri'
        WHEN 'inspection' THEN 'inspeksjon'
        ELSE 'service'
      END ||
      ' innen ' || to_char(r.due_date, 'DD.MM.YYYY') || '.';

    FOR u IN
      SELECT p.id, p.phone, p.full_name
      FROM public.profiles p
      WHERE p.id = ANY (r.notify_user_ids)
        AND p.phone IS NOT NULL
    LOOP
      PERFORM public.queue_sms(
        r.company_id,
        u.phone,
        msg,
        'equipment_reminder',
        'equipment_service_reminder',
        r.id
      );
      sent_count := sent_count + 1;
    END LOOP;

    UPDATE public.equipment_service_reminders
    SET sms_sent_at = now()
    WHERE id = r.id;
  END LOOP;

  RETURN sent_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_equipment_service_sms_reminders() TO service_role;

-- Send test-SMS til valgte ansatte (fra app)
CREATE OR REPLACE FUNCTION public.send_equipment_reminder_sms_now(p_reminder_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r public.equipment_service_reminders%ROWTYPE;
  eq public.equipment%ROWTYPE;
  u RECORD;
  msg TEXT;
  n INT := 0;
BEGIN
  SELECT * INTO r FROM public.equipment_service_reminders WHERE id = p_reminder_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Påminnelse ikke funnet'; END IF;
  IF r.company_id IS DISTINCT FROM public.current_user_company_id() THEN
    RAISE EXCEPTION 'Ingen tilgang';
  END IF;

  SELECT * INTO eq FROM public.equipment WHERE id = r.equipment_id;
  msg := 'DriftPro: ' || coalesce(eq.name, 'Truck') ||
    ' – ' || CASE r.reminder_type
      WHEN 'water_fill' THEN 'vann/batteri'
      WHEN 'inspection' THEN 'inspeksjon'
      ELSE 'service'
    END ||
    ' planlagt ' || to_char(r.due_date, 'DD.MM.YYYY') || '.';

  FOR u IN
    SELECT phone FROM public.profiles
    WHERE id = ANY (r.notify_user_ids) AND phone IS NOT NULL
  LOOP
    PERFORM public.queue_sms(r.company_id, u.phone, msg, 'equipment_reminder', 'equipment_service_reminder', r.id);
    n := n + 1;
  END LOOP;

  RETURN n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_equipment_reminder_sms_now(UUID) TO authenticated;
