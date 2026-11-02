-- Spar Edge Function-kvote: instant-triggere sender allerede.
-- Cron er kun backup, og kalles bare når det faktisk ligger usendte rader.

CREATE OR REPLACE FUNCTION public.sweep_notification_outboxes()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_base TEXT := 'https://ksnnyccthotjbrmgjgdc.supabase.co';
  v_anon TEXT := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtzbm55Y2N0aG90amJybWdqZ2RjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE4NDUzOTAsImV4cCI6MjA4NzQyMTM5MH0.P-TU43MSVNcTATUZkg6FLk4Mb1c0CclgPX6VjvvDul8';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.sms_outbox
    WHERE sent_at IS NULL AND attempts < 5
    LIMIT 1
  ) THEN
    PERFORM net.http_post(
      url := v_base || '/functions/v1/send-sms-outbox',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_anon,
        'apikey', v_anon
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 55000
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.email_outbox
    WHERE sent_at IS NULL AND attempts < 5
    LIMIT 1
  ) THEN
    PERFORM net.http_post(
      url := v_base || '/functions/v1/send-email-outbox',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_anon,
        'apikey', v_anon
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 120000
    );
  END IF;

  IF to_regclass('public.push_outbox') IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM public.push_outbox
       WHERE sent_at IS NULL AND attempts < 5
       LIMIT 1
     ) THEN
    PERFORM net.http_post(
      url := v_base || '/functions/v1/send-push-outbox',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_anon,
        'apikey', v_anon
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 55000
    );
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
$$;

COMMENT ON FUNCTION public.sweep_notification_outboxes() IS
  'Backup-flush av outbox kun når usendte rader finnes (spar Edge Function-kvote).';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
     OR NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    RAISE NOTICE 'pg_cron/pg_net ikke tilgjengelig — sett opp Cron i Dashboard';
    RETURN;
  END IF;

  BEGIN
    PERFORM cron.unschedule('driftpro-send-sms-outbox');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    PERFORM cron.unschedule('driftpro-send-email-outbox');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    PERFORM cron.unschedule('driftpro-sweep-outboxes');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- Hvert 5. minutt i stedet for hvert minutt × 2 workers.
  PERFORM cron.schedule(
    'driftpro-sweep-outboxes',
    '*/5 * * * *',
    $cron$SELECT public.sweep_notification_outboxes();$cron$
  );
END;
$$;
