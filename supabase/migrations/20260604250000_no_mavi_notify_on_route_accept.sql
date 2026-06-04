-- Ingen interne MAVI-varsler når samarbeidspartner aksepterer rute.
-- Kun avvisning skal varsle ledere/admin (partner_route_ack_internal).

CREATE OR REPLACE FUNCTION public.notify_internal_on_route_ack()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  p_name TEXT;
  sms_txt TEXT;
  sub TEXT;
  body TEXT;
BEGIN
  IF TG_OP <> 'UPDATE' THEN RETURN NEW; END IF;
  IF coalesce(OLD.ack_status, 'pending') = coalesce(NEW.ack_status, 'pending') THEN
    RETURN NEW;
  END IF;

  SELECT name INTO p_name FROM public.partners WHERE id = NEW.partner_id;

  -- Kun avvisning varsler MAVI internt — aksept er stille (partner har allerede bekreftet i portal).
  IF NEW.ack_status = 'rejected' THEN
    sub := 'Rute avvist: ' || coalesce(p_name, 'Partner');
    body := 'Status: ' || NEW.ack_status || E'\nKommentar: ' || coalesce(NEW.ack_comment, '-');
    sms_txt := 'MAVI: ' || coalesce(p_name, 'Partner') || ' har avvist rute.';

    PERFORM public.notify_mavi_partner_internal(
      NEW.company_id, 'partner_route_ack_internal',
      sub, body, sms_txt, 'partner_route_ack', 'partner_route_shares', NEW.id,
      'Partner avviste rute'
    );

    PERFORM public.notify_partner_owner_phones(
      NEW.company_id, NEW.partner_id,
      'Bekreftelse: ruten er registrert som avvist i DriftPro. Kontakt MAVI ved spørsmål.',
      'partner_route_rejected', 'partner_route_rejected',
      'partner_route_shares', NEW.id, 'Rute avvist (bekreftelse)'
    );
  ELSIF NEW.ack_status = 'accepted' THEN
    -- Ingen SMS/e-post til MAVI-ansatte ved aksept.
    NULL;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_internal_on_route_ack() IS
  'Varsler kun MAVI internt ved avvisning. Aksept fra partner er stille.';
