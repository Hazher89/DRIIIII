-- Add missing columns for onboarding
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_onboarded BOOLEAN DEFAULT FALSE;

-- Ensure RLS allows users to update their own onboarding status
-- (This policy should already exist but we make sure)
DROP POLICY IF EXISTS "Brukere kan oppdatere egen profil" ON profiles;
CREATE POLICY "Brukere kan oppdatere egen profil"
    ON profiles FOR UPDATE
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());
