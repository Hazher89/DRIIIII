-- Kiosk skal bruke selskapet der MAVI-ansatte faktisk ligger (employee_login_accounts),
-- ikke det tomme «DriftPro Demo AS»-selskapet.

CREATE OR REPLACE FUNCTION public.get_kiosk_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH ranked AS (
    SELECT
      c.id,
      (
        SELECT count(*)
        FROM public.employee_login_accounts ela
        WHERE ela.company_id = c.id
          AND ela.is_active
      ) AS employee_login_count,
      (
        SELECT count(*)
        FROM public.profiles p
        WHERE p.company_id = c.id
          AND p.partner_id IS NULL
          AND coalesce(p.is_active, true)
      ) AS profile_count
    FROM public.companies c
  )
  SELECT r.id
  FROM ranked r
  ORDER BY
    r.employee_login_count DESC,
    CASE
      WHEN (SELECT name FROM public.companies WHERE id = r.id) ILIKE '%mavi%' THEN 0
      WHEN (SELECT name FROM public.companies WHERE id = r.id) ILIKE '%logistikk%' THEN 1
      ELSE 2
    END,
    r.profile_count DESC,
    r.id
  LIMIT 1;
$$;

-- Vis riktig firmanavn på kiosk (ikke demo-navn).
UPDATE public.companies
SET name = 'MAVI Logistikk AS'
WHERE id = '00000000-0000-0000-0000-000000000000'::uuid
  AND name ILIKE '%demo%';

-- Fjern kiosk på feil selskap uten ansatte.
DELETE FROM public.time_clock_settings
WHERE company_id = 'd190e74c-393c-45da-9c18-6252e527693c'::uuid
  AND NOT EXISTS (
    SELECT 1
    FROM public.employee_login_accounts ela
    WHERE ela.company_id = time_clock_settings.company_id
      AND ela.is_active
  );

SELECT public.kiosk_bootstrap_default_company();
