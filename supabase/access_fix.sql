-- Legg til kolonne for tilgangskontroll hvis den ikke finnes
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS access_settings JSONB DEFAULT '{}'::JSONB;

-- Oppdater standard tilgang for eksisterende brukere
UPDATE profiles SET access_settings = '{
  "hms": true,
  "fravaer": true,
  "avvik": true,
  "avdelinger": true,
  "ansatte": true
}'::JSONB WHERE access_settings = '{}'::JSONB;

-- Gi admin/superadmin full tilgang uansett i koden (allerede håndtert i MainShell), 
-- men greit å ha i DB også.

-- Sørg for at RLS tillater admin å oppdatere denne kolonnen
DROP POLICY IF EXISTS "Admin kan oppdatere tilgangskontroll" ON profiles;
CREATE POLICY "Admin kan oppdatere tilgangskontroll"
    ON profiles FOR UPDATE
    TO authenticated
    USING ( (SELECT role FROM profiles WHERE id = auth.uid()) IN ('admin', 'superadmin') )
    WITH CHECK ( (SELECT role FROM profiles WHERE id = auth.uid()) IN ('admin', 'superadmin') );
