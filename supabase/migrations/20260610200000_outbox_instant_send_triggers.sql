-- Send e-post/SMS umiddelbart ved køing (pg_net → Edge Function), uten manuell ▶.

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.invoke_outbox_worker(
  p_function_name TEXT,
  p_ids UUID[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_base TEXT := 'https://ksnnyccthotjbrmgjgdc.supabase.co';
  v_anon TEXT := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtzbm55Y2N0aG90amJybWdqZ2RjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE4NDUzOTAsImV4cCI6MjA4NzQyMTM5MH0.P-TU43MSVNcTATUZkg6FLk4Mb1c0CclgPX6VjvvDul8';
  v_timeout INT;
BEGIN
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL THEN
    RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    RETURN;
  END IF;

  v_timeout := CASE
    WHEN p_function_name = 'send-email-outbox' THEN 120000
    ELSE 55000
  END;

  PERFORM net.http_post(
    url := v_base || '/functions/v1/' || p_function_name,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_anon,
      'apikey', v_anon
    ),
    body := jsonb_build_object('ids', to_jsonb(p_ids)),
    timeout_milliseconds := v_timeout
  );
EXCEPTION
  WHEN OTHERS THEN
    -- Cron/worker henter resten ved feil
    NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.trigger_email_outbox_send()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.invoke_outbox_worker('send-email-outbox', ARRAY[NEW.id]);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trigger_sms_outbox_send()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.invoke_outbox_worker('send-sms-outbox', ARRAY[NEW.id]);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_email_outbox_instant_send ON public.email_outbox;
CREATE TRIGGER trg_email_outbox_instant_send
  AFTER INSERT ON public.email_outbox
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_email_outbox_send();

DROP TRIGGER IF EXISTS trg_sms_outbox_instant_send ON public.sms_outbox;
CREATE TRIGGER trg_sms_outbox_instant_send
  AFTER INSERT ON public.sms_outbox
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_sms_outbox_send();

COMMENT ON FUNCTION public.invoke_outbox_worker IS
  'Kaller send-sms-outbox / send-email-outbox for spesifikke kø-rader (pg_net).';
