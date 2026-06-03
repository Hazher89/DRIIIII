-- Kjør send-sms-outbox og send-email-outbox hvert minutt (pg_cron + pg_net).
-- Bruker prosjekt-URL og anon JWT (samme som klienten; kun for å kalle Edge Functions).

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

DO $$
DECLARE
  v_url TEXT := 'https://ksnnyccthotjbrmgjgdc.supabase.co';
  v_anon TEXT := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtzbm55Y2N0aG90amJybWdqZ2RjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE4NDUzOTAsImV4cCI6MjA4NzQyMTM5MH0.P-TU43MSVNcTATUZkg6FLk4Mb1c0CclgPX6VjvvDul8';
  v_headers JSONB;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
     OR NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    RAISE NOTICE 'pg_cron/pg_net ikke tilgjengelig — sett opp Cron i Dashboard';
    RETURN;
  END IF;

  v_headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || v_anon,
    'apikey', v_anon
  );

  BEGIN
    PERFORM cron.unschedule('driftpro-send-sms-outbox');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    PERFORM cron.unschedule('driftpro-send-email-outbox');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  PERFORM cron.schedule(
    'driftpro-send-sms-outbox',
    '* * * * *',
    $cron$
    SELECT extensions.net.http_post(
      url := 'https://ksnnyccthotjbrmgjgdc.supabase.co/functions/v1/send-sms-outbox',
      headers := '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtzbm55Y2N0aG90amJybWdqZ2RjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE4NDUzOTAsImV4cCI6MjA4NzQyMTM5MH0.P-TU43MSVNcTATUZkg6FLk4Mb1c0CclgPX6VjvvDul8","apikey":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtzbm55Y2N0aG90amJybWdqZ2RjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE4NDUzOTAsImV4cCI6MjA4NzQyMTM5MH0.P-TU43MSVNcTATUZkg6FLk4Mb1c0CclgPX6VjvvDul8"}'::jsonb,
      body := '{}'::jsonb,
      timeout_milliseconds := 55000
    );
    $cron$
  );

  PERFORM cron.schedule(
    'driftpro-send-email-outbox',
    '* * * * *',
    $cron$
    SELECT extensions.net.http_post(
      url := 'https://ksnnyccthotjbrmgjgdc.supabase.co/functions/v1/send-email-outbox',
      headers := '{"Content-Type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtzbm55Y2N0aG90amJybWdqZ2RjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE4NDUzOTAsImV4cCI6MjA4NzQyMTM5MH0.P-TU43MSVNcTATUZkg6FLk4Mb1c0CclgPX6VjvvDul8","apikey":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtzbm55Y2N0aG90amJybWdqZ2RjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE4NDUzOTAsImV4cCI6MjA4NzQyMTM5MH0.P-TU43MSVNcTATUZkg6FLk4Mb1c0CclgPX6VjvvDul8"}'::jsonb,
      body := '{}'::jsonb,
      timeout_milliseconds := 120000
    );
    $cron$
  );
END;
$$;
