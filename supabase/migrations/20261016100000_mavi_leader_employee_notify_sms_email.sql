-- MAVI default: leder får SMS + e-post ved ny søknad/avvik;
-- ansatt får SMS + e-post ved godkjenning/avvisning/status.

UPDATE public.company_sms_settings
SET
  ch_absence_request = 'both'::public.notification_channel,
  ch_absence_decision = 'both'::public.notification_channel,
  ch_ticket_new = 'both'::public.notification_channel,
  ch_ticket_status = 'both'::public.notification_channel,
  ch_ticket_assigned = 'both'::public.notification_channel,
  sms_absence_request = true,
  sms_absence_decision = true,
  sms_ticket_new = true,
  sms_ticket_status = true,
  updated_at = now()
WHERE company_id = '00000000-0000-0000-0000-000000000000';

INSERT INTO public.company_notification_event_channels (
  company_id, event_id, sms_enabled, email_enabled, push_enabled
)
VALUES
  ('00000000-0000-0000-0000-000000000000', 'absence_request', true, true, true),
  ('00000000-0000-0000-0000-000000000000', 'absence_decision', true, true, true),
  ('00000000-0000-0000-0000-000000000000', 'ticket_new', true, true, true),
  ('00000000-0000-0000-0000-000000000000', 'ticket_status', true, true, true),
  ('00000000-0000-0000-0000-000000000000', 'ticket_assigned', true, true, true)
ON CONFLICT (company_id, event_id) DO UPDATE SET
  sms_enabled = EXCLUDED.sms_enabled,
  email_enabled = EXCLUDED.email_enabled,
  push_enabled = EXCLUDED.push_enabled;
