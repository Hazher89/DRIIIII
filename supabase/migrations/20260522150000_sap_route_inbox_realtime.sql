-- Live-oppdatering av SAP-innboks i DriftPro (badge uten manuell refresh).
ALTER TABLE public.sap_route_inbox REPLICA IDENTITY FULL;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.sap_route_inbox;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
