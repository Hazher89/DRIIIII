-- Oppstramming: cron bruker hms_check_sja_expiry (ikke hms_expire_overdue_sja).
-- Deaktiver gammel fravær-broadcast som kan kalles direkte.

CREATE OR REPLACE FUNCTION public.hms_check_sja_expiry()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec record;
BEGIN
  FOR rec IN
    SELECT s.*
    FROM public.sja_forms s
    WHERE s.status = 'i_gang'::public.sja_status
      AND s.valid_until IS NOT NULL
      AND s.valid_until < now()
      AND s.expired_notified_at IS NULL
  LOOP
    UPDATE public.sja_forms
    SET
      status = 'utlopt'::public.sja_status,
      expired_notified_at = now(),
      updated_at = now()
    WHERE id = rec.id;

    IF rec.responsible_person IS NOT NULL THEN
      PERFORM public.hms_notify_assigned_responsible(
        rec.company_id,
        rec.responsible_person,
        rec.title,
        'SJA utløpt — ny vurdering kreves',
        'sja_forms',
        rec.id,
        'hms_sja_expired',
        rec.created_by
      );
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.queue_absence_request_sms(p_absence public.absences)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Deaktivert: fravær varsles ikke automatisk til ledere/admin.
  RETURN;
END;
$$;

COMMENT ON FUNCTION public.hms_check_sja_expiry IS
  'Cron: marker utløpt SJA — varsler kun valgt ansvarlig person.';
COMMENT ON FUNCTION public.queue_absence_request_sms IS
  'Deaktivert — ingen masse-SMS ved nytt fravær.';
