-- SMS til superadmin når ny intern ansatt har fullført onboarding og venter godkjenning.
-- Kjør i Supabase SQL Editor ETTER sms_outbox_sveve.sql og sms_smart_notifications.sql.
--
-- Utløses når profiles.is_onboarded går false → true mens is_approved fortsatt er false.
-- Partner-portal (samarbeidspartner / partner_id) hoppes over.

ALTER TABLE public.company_sms_settings
  ADD COLUMN IF NOT EXISTS sms_user_approval BOOLEAN NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.company_sms_enabled(p_company_id UUID, p_key TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  s public.company_sms_settings%ROWTYPE;
BEGIN
  SELECT * INTO s FROM public.company_sms_settings WHERE company_id = p_company_id;
  IF NOT FOUND THEN
    RETURN true;
  END IF;
  CASE p_key
    WHEN 'absence_request' THEN RETURN s.sms_absence_request;
    WHEN 'absence_decision' THEN RETURN s.sms_absence_decision;
    WHEN 'ticket_new' THEN RETURN s.sms_ticket_new;
    WHEN 'ticket_status' THEN RETURN s.sms_ticket_status;
    WHEN 'ticket_critical' THEN RETURN s.sms_ticket_critical;
    WHEN 'equipment' THEN RETURN s.sms_equipment;
    WHEN 'user_approval' THEN RETURN s.sms_user_approval;
    ELSE RETURN s.sms_general;
  END CASE;
END;
$$;

CREATE OR REPLACE FUNCTION public.queue_user_approval_sms(p_profile public.profiles)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  admin_id UUID;
  dept_name TEXT;
  msg TEXT;
BEGIN
  IF p_profile.company_id IS NULL THEN
    RETURN;
  END IF;

  IF p_profile.role IN ('superadmin', 'samarbeidspartner') THEN
    RETURN;
  END IF;

  IF p_profile.partner_id IS NOT NULL THEN
    RETURN;
  END IF;

  IF p_profile.is_approved IS TRUE THEN
    RETURN;
  END IF;

  IF NOT public.company_sms_enabled(p_profile.company_id, 'user_approval') THEN
    RETURN;
  END IF;

  SELECT name INTO dept_name
  FROM public.departments
  WHERE id = p_profile.department_id;

  msg :=
    'Mavi: NY BRUKER VENTER GODKJENNING. '
    || COALESCE(NULLIF(trim(p_profile.full_name), ''), 'Ukjent navn')
    || COALESCE(' (' || NULLIF(trim(p_profile.email), '') || ')', '')
    || '. Avdeling: ' || COALESCE(dept_name, 'ikke valgt')
    || '. Åpne DriftPro → Ansatte.';

  FOR admin_id IN
    SELECT id
    FROM public.profiles
    WHERE company_id = p_profile.company_id
      AND role = 'superadmin'
      AND is_active = true
      AND is_approved = true
      AND phone_normalized IS NOT NULL
  LOOP
    PERFORM public.queue_sms_if_allowed(
      p_profile.company_id,
      admin_id,
      NULL,
      msg,
      'user_approval',
      'profiles',
      p_profile.id,
      'user_approval'
    );
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.queue_user_approval_sms(public.profiles) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.notify_superadmin_on_user_pending_approval()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF tg_op = 'UPDATE'
     AND COALESCE(OLD.is_onboarded, false) = false
     AND NEW.is_onboarded = true
     AND COALESCE(NEW.is_approved, false) = false THEN
    PERFORM public.queue_user_approval_sms(NEW);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_superadmin_user_pending_approval ON public.profiles;
CREATE TRIGGER trg_notify_superadmin_user_pending_approval
  AFTER UPDATE OF is_onboarded ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_superadmin_on_user_pending_approval();
