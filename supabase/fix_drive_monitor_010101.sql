-- Aktiver ansatt 010101 som leiebil-sporingsenhet (kjør i Supabase SQL Editor).

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS drive_monitor_device BOOLEAN NOT NULL DEFAULT false;

UPDATE public.profiles
SET
  drive_monitor_device = true,
  is_approved = true,
  is_onboarded = true,
  is_active = true,
  partner_id = NULL,
  partner_vehicle_id = NULL
WHERE trim(coalesce(employee_number, '')) = '010101';
