-- Tydeligere e-posttekst: sjåføravvik ≠ HMS-avvik for MAVI-ansatte.

CREATE OR REPLACE FUNCTION public.notify_partner_driver_deviation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enabled BOOLEAN := true;
  v_emails TEXT[] := '{}';
  v_email TEXT;
  v_subject TEXT;
  v_body TEXT;
BEGIN
  SELECT s.enabled, s.emails
  INTO v_enabled, v_emails
  FROM public.partner_driver_deviation_alert_settings s
  WHERE s.company_id = NEW.company_id;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;
  IF NOT coalesce(v_enabled, true) THEN
    RETURN NEW;
  END IF;

  v_subject := 'Nytt sjåføravvik (rute/kunde)'
    || CASE WHEN nullif(trim(NEW.order_ref), '') IS NOT NULL
      THEN ' – bilag ' || trim(NEW.order_ref)
      WHEN nullif(trim(NEW.freight_unit), '') IS NOT NULL
      THEN ' – FU ' || trim(NEW.freight_unit)
      ELSE '' END;
  v_body := concat_ws(E'\n',
    'Nytt sjåføravvik fra partner-sjåfør (rute/kunde).',
    'Dette er IKKE HMS-avvik for MAVI-ansatte.',
    'Dato: ' || to_char(NEW.route_date, 'DD.MM.YYYY'),
    CASE WHEN nullif(trim(NEW.order_ref), '') IS NOT NULL
      THEN 'Bilag: ' || trim(NEW.order_ref) END,
    CASE WHEN nullif(trim(NEW.freight_unit), '') IS NOT NULL
      THEN 'FU: ' || trim(NEW.freight_unit) END,
    CASE WHEN nullif(trim(NEW.customer_name), '') IS NOT NULL
      THEN 'Kunde: ' || trim(NEW.customer_name) END,
    'Kommentar: ' || trim(NEW.comment),
    '',
    'Åpne DriftPro → Partnere → Sjåføravvik.'
  );

  FOREACH v_email IN ARRAY coalesce(v_emails, '{}') LOOP
    IF nullif(trim(v_email), '') IS NOT NULL THEN
      PERFORM public.queue_email(
        NEW.company_id,
        lower(trim(v_email)),
        v_subject,
        v_body,
        'partner_driver_deviation',
        'partner_driver_deviation',
        NEW.id
      );
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

COMMENT ON TABLE public.partner_driver_deviations IS
  'Rute/kunde-avvik fra partner-sjåfører. Separat fra public.tickets (HMS-avvik for MAVI-ansatte).';
