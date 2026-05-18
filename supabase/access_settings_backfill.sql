-- Legg til NYE tilgangsnøkler for eksisterende admin/leder-profiler
-- (kun nøkler som mangler i access_settings — eksisterende true/false endres ikke)
-- Kjør i Supabase SQL Editor etter deploy av app 72e8f30+

DO $$
DECLARE
  new_keys TEXT[] := ARRAY[
    'partners',
    'fleet_ruter',
    'partners_admin',
    'ferie_admin',
    'fravaer_godkjenn',
    'fravaer_registrer_andre',
    'ansatte_rediger',
    'hms_utstyr',
    'hms_utstyr_admin',
    'hms_utstyr_service',
    'hms_utstyr_servicehefte',
    'hms_kompetanse',
    'hms_risikomatrise'
  ];
  k TEXT;
  r RECORD;
  patch JSONB;
BEGIN
  FOR r IN
    SELECT id, role, access_settings
    FROM public.profiles
    WHERE role IN ('admin', 'leder')
      AND is_active = true
      AND partner_id IS NULL
  LOOP
    patch := '{}'::jsonb;
    FOREACH k IN ARRAY new_keys LOOP
      IF coalesce(r.access_settings, '{}'::jsonb) ? k THEN
        CONTINUE;
      END IF;
      IF r.role = 'admin' THEN
        patch := patch || jsonb_build_object(k, true);
      ELSIF r.role = 'leder' AND k IN (
        'partners', 'fleet_ruter', 'partners_admin',
        'fravaer_godkjenn', 'fravaer_registrer_andre',
        'ansatte', 'ansatte_rediger'
      ) THEN
        patch := patch || jsonb_build_object(k, true);
      END IF;
    END LOOP;
    IF patch <> '{}'::jsonb THEN
      UPDATE public.profiles
      SET access_settings = coalesce(access_settings, '{}'::jsonb) || patch
      WHERE id = r.id;
    END IF;
  END LOOP;
END;
$$;
