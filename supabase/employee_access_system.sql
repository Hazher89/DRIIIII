-- Granulær tilgangskontroll + streng godkjenning av nye ansatte
-- Kjør i Supabase SQL Editor

-- Nye brukere: ingen modultilgang før superadmin godkjenner
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  default_company_id UUID;
BEGIN
  SELECT id INTO default_company_id FROM public.companies LIMIT 1;

  INSERT INTO public.profiles (
    id,
    email,
    full_name,
    company_id,
    role,
    access_settings,
    is_onboarded,
    is_approved
  )
  VALUES (
    new.id,
    new.email,
    COALESCE(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', 'Ny bruker'),
    default_company_id,
    CASE
      WHEN new.email IN ('baxightsi@gmail.com') THEN 'superadmin'::user_role
      ELSE 'ansatt'::user_role
    END,
    '{}'::JSONB,
    FALSE,
    CASE WHEN new.email IN ('baxightsi@gmail.com') THEN TRUE ELSE FALSE END
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = COALESCE(public.profiles.full_name, EXCLUDED.full_name);

  RETURN new;
EXCEPTION WHEN OTHERS THEN
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Godkjenn ansatt med rolle og tilganger (kun superadmin)
CREATE OR REPLACE FUNCTION public.approve_employee_profile(
  p_profile_id UUID,
  p_role public.user_role,
  p_department_id UUID,
  p_access_settings JSONB,
  p_set_department_leader BOOLEAN DEFAULT FALSE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  requester_role public.user_role;
  requester_company UUID;
  target_company UUID;
BEGIN
  SELECT role, company_id INTO requester_role, requester_company
  FROM public.profiles WHERE id = auth.uid();

  IF requester_role IS DISTINCT FROM 'superadmin' THEN
    RAISE EXCEPTION 'Kun superadmin kan godkjenne nye ansatte';
  END IF;

  SELECT company_id INTO target_company FROM public.profiles WHERE id = p_profile_id;
  IF target_company IS NULL OR target_company IS DISTINCT FROM requester_company THEN
    RAISE EXCEPTION 'Bruker tilhører ikke ditt selskap';
  END IF;

  UPDATE public.profiles
  SET
    role = p_role,
    department_id = p_department_id,
    access_settings = COALESCE(p_access_settings, '{}'::JSONB),
    is_approved = TRUE,
    is_active = TRUE,
    is_onboarded = TRUE
  WHERE id = p_profile_id;

  IF p_set_department_leader AND p_department_id IS NOT NULL AND p_role = 'leder' THEN
    UPDATE public.departments
    SET leader_id = p_profile_id
    WHERE id = p_department_id AND company_id = target_company;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.approve_employee_profile(UUID, public.user_role, UUID, JSONB, BOOLEAN)
  TO authenticated;
