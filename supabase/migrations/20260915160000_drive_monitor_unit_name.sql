-- Sporingsenheter: eget navn per enhet (ikke partner/MAVI-bil).
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS drive_monitor_unit_name TEXT;

COMMENT ON COLUMN public.profiles.drive_monitor_unit_name IS
  'Visningsnavn for leiebil-/sporingsenhet (f.eks. Bil 3, iPad lager).';
