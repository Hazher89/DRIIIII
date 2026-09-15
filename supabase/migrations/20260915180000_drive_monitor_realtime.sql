-- Live-oppdatering i hub når Android synker GPS.
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.drive_monitor_samples;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.drive_monitor_events;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.drive_monitor_sessions;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;
