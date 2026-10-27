-- Sjåføravvik: telefon i søk; search_text dekker navn/tlf/21/22/60/39/41.
-- Status beholdes i DB men brukes ikke i UI (kun registrering).

ALTER TABLE public.partner_driver_deviations
  ADD COLUMN IF NOT EXISTS customer_phone TEXT;

COMMENT ON COLUMN public.partner_driver_deviations.customer_phone IS
  'Kunden telefon fra rute-PDF — søkbar for CCC/butikk/MAVI.';

CREATE OR REPLACE FUNCTION public.partner_driver_deviations_set_search_text()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  phone_digits TEXT;
BEGIN
  phone_digits := regexp_replace(coalesce(NEW.customer_phone, ''), '[^0-9]', '', 'g');
  IF phone_digits LIKE '47%' AND length(phone_digits) >= 10 THEN
    phone_digits := substr(phone_digits, 3);
  ELSIF phone_digits LIKE '0047%' AND length(phone_digits) >= 12 THEN
    phone_digits := substr(phone_digits, 5);
  END IF;

  NEW.search_text := lower(trim(both FROM concat_ws(
    ' ',
    coalesce(NEW.freight_unit, ''),
    coalesce(NEW.customer_ref, ''),
    coalesce(NEW.order_ref, ''),
    coalesce(NEW.customer_name, ''),
    coalesce(NEW.customer_phone, ''),
    phone_digits,
    coalesce(NEW.comment, ''),
    coalesce(NEW.reporter_name, '')
  )));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_partner_driver_deviations_search_text
  ON public.partner_driver_deviations;
CREATE TRIGGER trg_partner_driver_deviations_search_text
  BEFORE INSERT OR UPDATE OF freight_unit, customer_ref, order_ref,
    customer_name, customer_phone, comment, reporter_name
  ON public.partner_driver_deviations
  FOR EACH ROW EXECUTE FUNCTION public.partner_driver_deviations_set_search_text();

-- Oppdater search_text for eksisterende rader.
UPDATE public.partner_driver_deviations
SET comment = comment
WHERE true;
