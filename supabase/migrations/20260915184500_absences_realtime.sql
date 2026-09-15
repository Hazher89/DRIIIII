-- Live-oppdatering av ferie/fravær-kalender ved godkjenning, endring og sletting.
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.absences;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;

ALTER TABLE public.absences REPLICA IDENTITY FULL;
