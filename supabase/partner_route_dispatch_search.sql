-- Rutefordeling: staging før utsendelse, PDF-tekst for smart søk
-- Kjør etter fleet_route_shifts_dashboard.sql og route_ack_and_email_notifications.sql

ALTER TABLE public.partner_route_shares
  ADD COLUMN IF NOT EXISTS dispatch_status TEXT NOT NULL DEFAULT 'sent';

ALTER TABLE public.partner_route_shares
  ADD COLUMN IF NOT EXISTS pdf_search_text TEXT;

CREATE INDEX IF NOT EXISTS idx_route_shares_dispatch
  ON public.partner_route_shares(company_id, dispatch_status, share_date DESC);

CREATE INDEX IF NOT EXISTS idx_route_shares_pdf_search
  ON public.partner_route_shares USING gin (to_tsvector('simple', coalesce(pdf_search_text, '')));

COMMENT ON COLUMN public.partner_route_shares.dispatch_status IS 'staged = fordelt internt, ikke sendt til sjåfør; sent = synlig i portal';

-- Varsle partner kun når rute er sendt (ikke ved staging)
CREATE OR REPLACE FUNCTION public.notify_partner_on_route_share()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  fallback_partner_email TEXT;
BEGIN
  IF TG_OP = 'INSERT' AND COALESCE(NEW.dispatch_status, 'sent') <> 'sent' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF COALESCE(OLD.dispatch_status, 'staged') = 'sent' OR COALESCE(NEW.dispatch_status, 'staged') <> 'sent' THEN
      RETURN NEW;
    END IF;
  END IF;

  FOR rec IN
    SELECT login_email AS email
    FROM public.partner_portal_accounts
    WHERE partner_id = NEW.partner_id
      AND is_active = true
      AND COALESCE(login_email, '') <> ''
  LOOP
    PERFORM public.queue_email(
      NEW.company_id,
      rec.email,
      'Ny rute er sendt til dere i DriftPro',
      'Dere har mottatt en ny rute-PDF. Logg inn i DriftPro partnerportal for aa aapne og akseptere/avvise ruten.',
      'partner_route_share',
      'partner_route_shares',
      NEW.id
    );
  END LOOP;

  SELECT p.email INTO fallback_partner_email
  FROM public.partners p
  WHERE p.id = NEW.partner_id;

  IF fallback_partner_email IS NOT NULL AND length(trim(fallback_partner_email)) > 0 THEN
    PERFORM public.queue_email(
      NEW.company_id,
      fallback_partner_email,
      'Ny rute er sendt til dere i DriftPro',
      'Dere har mottatt en ny rute-PDF. Logg inn i DriftPro partnerportal for aa aapne og akseptere/avvise ruten.',
      'partner_route_share',
      'partner_route_shares',
      NEW.id
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_partner_on_route_share ON public.partner_route_shares;
CREATE TRIGGER trg_notify_partner_on_route_share
AFTER INSERT ON public.partner_route_shares
FOR EACH ROW EXECUTE FUNCTION public.notify_partner_on_route_share();

DROP TRIGGER IF EXISTS trg_notify_partner_on_route_share_sent ON public.partner_route_shares;
CREATE TRIGGER trg_notify_partner_on_route_share_sent
AFTER UPDATE OF dispatch_status ON public.partner_route_shares
FOR EACH ROW EXECUTE FUNCTION public.notify_partner_on_route_share();
