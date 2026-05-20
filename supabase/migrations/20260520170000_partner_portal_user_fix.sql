-- Fiks «Database error creating new user» for bil-eier / sjåfør-portaler.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON e.enumtypid = t.oid
    JOIN pg_namespace n ON t.typnamespace = n.oid
    WHERE n.nspname = 'public' AND t.typname = 'user_role'
      AND e.enumlabel = 'samarbeidspartner'
  ) THEN
    ALTER TYPE public.user_role ADD VALUE 'samarbeidspartner';
  END IF;
END
$$;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS partner_id UUID REFERENCES public.partners(id) ON DELETE SET NULL;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS partner_vehicle_id UUID REFERENCES public.partner_vehicles(id) ON DELETE SET NULL;

ALTER TABLE public.partner_portal_accounts
  ADD COLUMN IF NOT EXISTS account_kind TEXT NOT NULL DEFAULT 'driver';

ALTER TABLE public.partner_portal_accounts
  DROP CONSTRAINT IF EXISTS partner_portal_accounts_account_kind_check;

ALTER TABLE public.partner_portal_accounts
  ADD CONSTRAINT partner_portal_accounts_account_kind_check
  CHECK (account_kind IN ('owner', 'driver'));

CREATE UNIQUE INDEX IF NOT EXISTS idx_partner_portal_owner_unique
  ON public.partner_portal_accounts(partner_id)
  WHERE account_kind = 'owner' AND is_active = true;

-- handle_new_user: støtt portal_provision metadata fra Edge Function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  default_company_id UUID;
  is_superadmin_account BOOLEAN;
  portal_provision BOOLEAN;
  meta_company_id UUID;
  meta_partner_id UUID;
  meta_vehicle_id UUID;
  meta_phone TEXT;
BEGIN
  is_superadmin_account := lower(coalesce(new.email, '')) IN (
    'baxigshti@gmail.com',
    'baxightsi@gmail.com',
    'baxigshti@hotmail.de',
    'baxlgshtl@gmail.com'
  );

  portal_provision :=
    COALESCE(new.raw_user_meta_data->>'portal_provision', '') IN ('true', '1', 'yes');

  IF portal_provision
     AND trim(COALESCE(new.raw_user_meta_data->>'company_id', '')) <> '' THEN
    BEGIN
      meta_company_id := (new.raw_user_meta_data->>'company_id')::uuid;
    EXCEPTION
      WHEN invalid_text_representation THEN
        meta_company_id := NULL;
    END;

    IF trim(COALESCE(new.raw_user_meta_data->>'partner_id', '')) <> '' THEN
      BEGIN
        meta_partner_id := (new.raw_user_meta_data->>'partner_id')::uuid;
      EXCEPTION
        WHEN invalid_text_representation THEN
          meta_partner_id := NULL;
      END;
    END IF;

    meta_vehicle_id := NULL;
    IF trim(COALESCE(new.raw_user_meta_data->>'partner_vehicle_id', '')) <> '' THEN
      BEGIN
        meta_vehicle_id := (new.raw_user_meta_data->>'partner_vehicle_id')::uuid;
      EXCEPTION
        WHEN invalid_text_representation THEN
          meta_vehicle_id := NULL;
      END;
    END IF;

    meta_phone := nullif(trim(new.raw_user_meta_data->>'phone'), '');

    IF meta_company_id IS NOT NULL THEN
      INSERT INTO public.profiles (
        id,
        email,
        full_name,
        company_id,
        role,
        access_settings,
        is_onboarded,
        is_approved,
        is_active,
        partner_id,
        partner_vehicle_id,
        phone
      )
      VALUES (
        new.id,
        new.email,
        COALESCE(
          new.raw_user_meta_data->>'full_name',
          new.raw_user_meta_data->>'name',
          split_part(coalesce(new.email, 'portal'), '@', 1)
        ),
        meta_company_id,
        'samarbeidspartner'::public.user_role,
        '{}'::jsonb,
        TRUE,
        TRUE,
        TRUE,
        meta_partner_id,
        meta_vehicle_id,
        meta_phone
      )
      ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        full_name = COALESCE(public.profiles.full_name, EXCLUDED.full_name),
        company_id = EXCLUDED.company_id,
        partner_id = EXCLUDED.partner_id,
        partner_vehicle_id = EXCLUDED.partner_vehicle_id,
        phone = COALESCE(EXCLUDED.phone, public.profiles.phone),
        role = 'samarbeidspartner'::public.user_role,
        is_onboarded = TRUE,
        is_approved = TRUE,
        is_active = TRUE;
      RETURN new;
    END IF;
  END IF;

  SELECT id INTO default_company_id FROM public.companies LIMIT 1;

  INSERT INTO public.profiles (
    id,
    email,
    full_name,
    company_id,
    role,
    access_settings,
    is_onboarded,
    is_approved,
    is_active
  )
  VALUES (
    new.id,
    new.email,
    COALESCE(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      'Ny bruker'
    ),
    default_company_id,
    CASE
      WHEN is_superadmin_account THEN 'superadmin'::public.user_role
      ELSE 'ansatt'::public.user_role
    END,
    '{}'::jsonb,
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
