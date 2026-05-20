-- Fiks superadmin for baxigshti@gmail.com (kjør i Supabase SQL Editor)
-- OBS: «handle_new_user» nedenfor er eldre variant. For partner-portal (bil-eier/MAVI),
--     kjør også partner_portal_handle_new_user_fix.sql så triggeren støtter metadata.
-- Deretter: logg ut i appen og logg inn på nytt

UPDATE public.profiles
SET
  role = 'superadmin',
  is_approved = TRUE,
  is_onboarded = TRUE,
  is_active = TRUE,
  access_settings = (
    SELECT jsonb_object_agg(key, true)
    FROM (
      SELECT unnest(ARRAY[
        'dashboard', 'surveys', 'fravaer', 'avvik', 'hms', 'partners', 'more',
        'avdelinger', 'ansatte', 'personalmappe', 'varsler', 'undersokelser',
        'whistleblowing', 'kiosk', 'tilgangskontroll', 'brukergodkjenning',
        'samarbeidspartnere', 'profil', 'app_innstillinger',
        'fravaer_godkjenn', 'fravaer_registrer_andre', 'ferie_admin',
        'avvik_godkjenn', 'avvik_koordinere', 'avvik_admin',
        'hms_risikovurdering', 'hms_sja', 'hms_sikkerhetsrunde', 'hms_risikomatrise',
        'hms_utstyr', 'hms_utstyr_admin', 'hms_utstyr_service', 'hms_utstyr_servicehefte',
        'hms_kompetanse', 'hms_dokumenter', 'survey_bygge', 'survey_resultater',
        'partners_admin', 'fleet_ruter', 'ansatte_rediger', 'avdelinger_rediger'
      ]) AS key
    ) t
  )
WHERE lower(email) IN (
  'baxigshti@gmail.com',
  'baxightsi@gmail.com',
  'baxigshti@hotmail.de',
  'baxlgshtl@gmail.com'
);

-- Oppdater trigger for nye registreringer
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  default_company_id UUID;
  is_superadmin_account BOOLEAN;
BEGIN
  is_superadmin_account := lower(new.email) IN (
    'baxigshti@gmail.com',
    'baxightsi@gmail.com',
    'baxigshti@hotmail.de',
    'baxlgshtl@gmail.com'
  );

  SELECT id INTO default_company_id FROM public.companies LIMIT 1;

  INSERT INTO public.profiles (
    id, email, full_name, company_id, role, access_settings, is_onboarded, is_approved, is_active
  )
  VALUES (
    new.id,
    new.email,
    COALESCE(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', 'Ny bruker'),
    default_company_id,
    CASE WHEN is_superadmin_account THEN 'superadmin'::user_role ELSE 'ansatt'::user_role END,
    '{}'::JSONB,
    CASE WHEN is_superadmin_account THEN TRUE ELSE FALSE END,
    CASE WHEN is_superadmin_account THEN TRUE ELSE FALSE END,
    TRUE
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = COALESCE(public.profiles.full_name, EXCLUDED.full_name);

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
