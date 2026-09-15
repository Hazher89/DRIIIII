-- Skritt på jobb (MAVI ansatte) — frivillig, kun arbeidssted, ingen sporing.
-- Formål: kun for MAVI og egne ansatte. Ingen tredjepartsdeling. Ingen kontinuerlig tracking.
-- Ansatte kan slå av når som helst. Hub viser kun aggregerte skritt lagret ved frivillig synk på arbeidssted.

CREATE TABLE IF NOT EXISTS public.company_work_steps_settings (
  company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  enabled BOOLEAN NOT NULL DEFAULT true,
  workplace_name TEXT NOT NULL DEFAULT 'Arbeidssted',
  workplace_lat DOUBLE PRECISION,
  workplace_lng DOUBLE PRECISION,
  radius_meters INT NOT NULL DEFAULT 200 CHECK (radius_meters BETWEEN 50 AND 2000),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

COMMENT ON TABLE public.company_work_steps_settings IS
  'MAVI arbeidssted for frivillig skritt-på-jobb. Ingen tracking — kun geofence-sjekk ved manuell/valgfri synk.';

CREATE TABLE IF NOT EXISTS public.employee_work_steps_consent (
  profile_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  enabled BOOLEAN NOT NULL DEFAULT false,
  consent_version TEXT NOT NULL DEFAULT 'work_steps_v1',
  consented_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_employee_work_steps_consent_company
  ON public.employee_work_steps_consent (company_id, enabled);

COMMENT ON TABLE public.employee_work_steps_consent IS
  'Frivillig samtykke for skritt på jobb. Ansatte kan slå av når som helst. Kun MAVI-ansatte.';

CREATE TABLE IF NOT EXISTS public.employee_work_steps_daily (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  work_date DATE NOT NULL,
  steps_at_work INT NOT NULL DEFAULT 0 CHECK (steps_at_work >= 0),
  synced_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  at_workplace BOOLEAN NOT NULL DEFAULT true,
  source TEXT NOT NULL DEFAULT 'health_kit_or_health_connect',
  UNIQUE (profile_id, work_date)
);

CREATE INDEX IF NOT EXISTS idx_employee_work_steps_daily_company_date
  ON public.employee_work_steps_daily (company_id, work_date DESC);

COMMENT ON TABLE public.employee_work_steps_daily IS
  'Daglige skritt lagret kun når ansatt har samtykket og telefonen er innenfor MAVI arbeidssted ved synk. Ingen GPS-spor.';

ALTER TABLE public.company_work_steps_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_work_steps_consent ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.employee_work_steps_daily ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS company_work_steps_settings_select ON public.company_work_steps_settings;
CREATE POLICY company_work_steps_settings_select
  ON public.company_work_steps_settings FOR SELECT TO authenticated
  USING (company_id = public.get_user_company_id());

DROP POLICY IF EXISTS company_work_steps_settings_write ON public.company_work_steps_settings;
CREATE POLICY company_work_steps_settings_write
  ON public.company_work_steps_settings FOR ALL TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      public.is_company_admin()
      OR public.get_user_role() IN (
        'admin'::public.user_role,
        'superadmin'::public.user_role,
        'leder'::public.user_role
      )
      OR public.profile_has_access(auth.uid(), 'more.work_steps_hub', 'view')
    )
  )
  WITH CHECK (company_id = public.get_user_company_id());

DROP POLICY IF EXISTS employee_work_steps_consent_select ON public.employee_work_steps_consent;
CREATE POLICY employee_work_steps_consent_select
  ON public.employee_work_steps_consent FOR SELECT TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      profile_id = auth.uid()
      OR public.is_company_admin()
      OR public.get_user_role() IN (
        'admin'::public.user_role,
        'superadmin'::public.user_role,
        'leder'::public.user_role
      )
      OR public.profile_has_access(auth.uid(), 'more.work_steps_hub', 'view')
    )
  );

DROP POLICY IF EXISTS employee_work_steps_consent_self ON public.employee_work_steps_consent;
CREATE POLICY employee_work_steps_consent_self
  ON public.employee_work_steps_consent FOR ALL TO authenticated
  USING (profile_id = auth.uid() AND company_id = public.get_user_company_id())
  WITH CHECK (profile_id = auth.uid() AND company_id = public.get_user_company_id());

DROP POLICY IF EXISTS employee_work_steps_daily_select ON public.employee_work_steps_daily;
CREATE POLICY employee_work_steps_daily_select
  ON public.employee_work_steps_daily FOR SELECT TO authenticated
  USING (
    company_id = public.get_user_company_id()
    AND (
      profile_id = auth.uid()
      OR public.is_company_admin()
      OR public.get_user_role() IN (
        'admin'::public.user_role,
        'superadmin'::public.user_role,
        'leder'::public.user_role
      )
      OR public.profile_has_access(auth.uid(), 'more.work_steps_hub', 'view')
    )
  );

DROP POLICY IF EXISTS employee_work_steps_daily_self_write ON public.employee_work_steps_daily;
CREATE POLICY employee_work_steps_daily_self_write
  ON public.employee_work_steps_daily FOR ALL TO authenticated
  USING (profile_id = auth.uid() AND company_id = public.get_user_company_id())
  WITH CHECK (profile_id = auth.uid() AND company_id = public.get_user_company_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.company_work_steps_settings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employee_work_steps_consent TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employee_work_steps_daily TO authenticated;

-- Hub-oversikt: aggregerte tall uten rå GPS.
CREATE OR REPLACE FUNCTION public.get_work_steps_hub_overview(
  p_from DATE DEFAULT (CURRENT_DATE - 14),
  p_to DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
  profile_id UUID,
  full_name TEXT,
  employee_number TEXT,
  consent_enabled BOOLEAN,
  steps_today INT,
  steps_period INT,
  days_with_data INT,
  last_synced_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company UUID := public.get_user_company_id();
BEGIN
  IF auth.uid() IS NULL OR v_company IS NULL THEN
    RETURN;
  END IF;

  IF NOT (
    public.is_company_admin()
    OR public.get_user_role() IN (
      'admin'::public.user_role,
      'superadmin'::public.user_role,
      'leder'::public.user_role
    )
    OR public.profile_has_access(auth.uid(), 'more.work_steps_hub', 'view')
  ) THEN
    RAISE EXCEPTION 'Ingen tilgang til skritt-oversikt';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    coalesce(nullif(trim(p.full_name), ''), p.email, 'Ukjent')::text,
    nullif(trim(p.employee_number), '')::text,
    coalesce(c.enabled, false),
    coalesce((
      SELECT d.steps_at_work
      FROM public.employee_work_steps_daily d
      WHERE d.profile_id = p.id AND d.work_date = CURRENT_DATE
    ), 0)::int,
    coalesce((
      SELECT sum(d.steps_at_work)::int
      FROM public.employee_work_steps_daily d
      WHERE d.profile_id = p.id
        AND d.work_date BETWEEN p_from AND p_to
    ), 0),
    coalesce((
      SELECT count(*)::int
      FROM public.employee_work_steps_daily d
      WHERE d.profile_id = p.id
        AND d.work_date BETWEEN p_from AND p_to
        AND d.steps_at_work > 0
    ), 0),
    (
      SELECT max(d.synced_at)
      FROM public.employee_work_steps_daily d
      WHERE d.profile_id = p.id
    )
  FROM public.profiles p
  LEFT JOIN public.employee_work_steps_consent c ON c.profile_id = p.id
  WHERE p.company_id = v_company
    AND coalesce(p.is_active, true)
    AND p.role IS DISTINCT FROM 'samarbeidspartner'::public.user_role
    AND p.partner_id IS NULL
  ORDER BY coalesce(c.enabled, false) DESC, full_name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_work_steps_hub_overview(DATE, DATE) TO authenticated;
