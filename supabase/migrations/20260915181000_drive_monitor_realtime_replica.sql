-- Realtime-filtre på company_id krever FULL replica identity.
ALTER TABLE public.drive_monitor_samples REPLICA IDENTITY FULL;
ALTER TABLE public.drive_monitor_events REPLICA IDENTITY FULL;
ALTER TABLE public.drive_monitor_sessions REPLICA IDENTITY FULL;
