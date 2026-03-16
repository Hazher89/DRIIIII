-- ============================================================
-- DRIFTPRO – SUPER-ADMIN & MANAGEMENT FIX
-- Run this in Supabase SQL Editor
-- ============================================================

-- 1. Ensure a default company exists if none are present
-- This ensures users can be linked to a company.
INSERT INTO companies (name, org_number)
SELECT 'DriftPro Hovedkontor', '999999999'
WHERE NOT EXISTS (SELECT 1 FROM companies LIMIT 1);

-- 2. Update RLS for PROFILES
-- Ensure SuperAdmins can manage everyone, and Leaders can see their department.
DROP POLICY IF EXISTS "Brukere kan se profiler i eget selskap" ON profiles;
CREATE POLICY "Brukere kan se profiler i eget selskap"
    ON profiles FOR SELECT
    USING (company_id = get_user_company_id());

DROP POLICY IF EXISTS "Admin kan oppdatere alle profiler i selskapet" ON profiles;
CREATE POLICY "Admin kan administrere alle profiler"
    ON profiles FOR ALL
    USING (
        get_user_role() IN ('admin', 'superadmin')
        AND company_id = get_user_company_id()
    );

-- 3. Update RLS for DEPARTMENTS
DROP POLICY IF EXISTS "Admin kan administrere avdelinger" ON departments;
CREATE POLICY "Ledere og Admin kan administrere avdelinger"
    ON departments FOR ALL
    USING (
        (get_user_role() IN ('admin', 'superadmin'))
        OR (get_user_role() = 'leder' AND leader_id = auth.uid())
    );

-- 4. Update RLS for ABSENCES (Fravær)
-- Allow Leaders to manage (Insert/Update/Delete) for their department
DROP POLICY IF EXISTS "Ledere kan se fravær i sin avdeling" ON absences;
CREATE POLICY "Ledere kan se fravær i sin avdeling"
    ON absences FOR SELECT
    USING (
        department_id = get_user_department_id()
        OR get_user_role() IN ('admin', 'superadmin')
    );

DROP POLICY IF EXISTS "Ledere kan godkjenne fravær i sin avdeling" ON absences;
CREATE POLICY "Ledere og Admin kan administrere fravær"
    ON absences FOR ALL
    USING (
        get_user_role() IN ('admin', 'superadmin')
        OR (
            get_user_role() = 'leder' 
            AND department_id = get_user_department_id()
        )
    );

-- 5. Update RLS for ABSENCE QUOTAS (Feriedager)
-- Important: Leaders need to be able to change vacation days!
DROP POLICY IF EXISTS "Admin kan se alle kvoter i selskapet" ON absence_quotas;
CREATE POLICY "Ledere og Admin kan administrere kvoter"
    ON absence_quotas FOR ALL
    USING (
        get_user_role() IN ('admin', 'superadmin')
        OR (
            get_user_role() = 'leder'
            AND EXISTS (
                SELECT 1 FROM profiles 
                WHERE profiles.id = absence_quotas.user_id 
                AND profiles.department_id = get_user_department_id()
            )
        )
    );

-- 6. SETUP THE SYSTEM SUPERADMIN
-- This identifying the user by email and elevating them.
-- NOTE: The user must have logged in at least once for the profile to exist.
UPDATE profiles 
SET role = 'superadmin' 
WHERE email = 'baxightsi@gmail.com';

-- 7. Ensure consistency for other tables (Tickets, Risk, SJA)
-- Ensure SuperAdmin bypasses all filters
DROP POLICY IF EXISTS "Ansatte kan se avvik i sin avdeling" ON tickets;
CREATE POLICY "Tickets tilgang"
    ON tickets FOR SELECT
    USING (
        company_id = get_user_company_id()
        AND (
            reported_by = auth.uid()
            OR department_id = get_user_department_id()
            OR get_user_role() IN ('admin', 'superadmin')
        )
    );

-- Helper to make sure Admin can delete anything if needed (cleanup)
CREATE POLICY "Superadmin full slette-tilgang"
    ON audit_log FOR ALL
    USING (get_user_role() = 'superadmin');

-- Final check: If user baxightsi@gmail.com is NOT in profiles yet, 
-- they might be stuck because of RLS on profiles insert.
-- Let's make sure the trigger for profile creation is robust.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, company_id, role)
  VALUES (
    new.id, 
    new.email, 
    COALESCE(new.raw_user_meta_data->>'full_name', new.email),
    (SELECT id FROM public.companies LIMIT 1), -- Default to first company
    CASE WHEN new.email = 'baxightsi@gmail.com' THEN 'superadmin'::user_role ELSE 'ansatt'::user_role END
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-create the trigger (drops and creates)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
