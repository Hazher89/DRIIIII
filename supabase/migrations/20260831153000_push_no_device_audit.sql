-- Logg når push-varsler ikke finner noen enheter (typisk: FCM-token ikke registrert).

CREATE OR REPLACE FUNCTION public.notify_partner_deduction_owner_push(
  p_company_id UUID,
  p_partner_id UUID,
  p_case_id UUID,
  p_title TEXT,
  p_body TEXT
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d RECORD;
  n INT := 0;
BEGIN
  IF NOT public.company_partner_push_enabled(p_company_id, 'partner_deduction') THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'push', 'partner_deduction', 'partner_deduction',
      NULL, NULL, 'skipped', 'company_channel_off',
      'Bot/trekk push av i firmainnstillinger', NULL, NULL, NULL,
      'partner_deduction_cases', p_case_id
    );
    RETURN 0;
  END IF;

  FOR d IN
    SELECT DISTINCT ppa.profile_id
    FROM public.partner_portal_accounts ppa
    JOIN public.profiles pr ON pr.id = ppa.profile_id AND coalesce(pr.is_active, true) = true
    WHERE ppa.partner_id = p_partner_id
      AND ppa.is_active = true
      AND ppa.profile_id IS NOT NULL
      AND coalesce(ppa.account_kind, 'owner') IN ('owner', 'admin')
      AND ppa.partner_vehicle_id IS NULL
  LOOP
    n := n + public.queue_push_to_profile_if_allowed(
      p_company_id,
      d.profile_id,
      p_title,
      p_body,
      'partner_deduction',
      'partner_deduction_cases',
      p_case_id,
      'partner_deduction',
      'Bot/trekk → bedriftsansvarlig (push)',
      true,
      jsonb_build_object('type', 'partner_deduction', 'case_id', p_case_id::text)
    );
  END LOOP;

  IF n = 0 THEN
    PERFORM public.log_notification_audit(
      p_company_id, 'push', 'partner_deduction', 'partner_deduction',
      NULL, NULL, 'skipped', 'no_push_devices',
      'Ingen aktiv push-enhet for bedriftsansvarlig — logg inn i appen og slå på varsler',
      NULL, NULL, NULL,
      'partner_deduction_cases', p_case_id
    );
  END IF;

  RETURN n;
END;
$$;
