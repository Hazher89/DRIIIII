-- Smart utstyr & maskiner (truck, elektronikk, service, varsler, arkiv)
-- Kjør etter hms_platform_enhancement.sql

-- Utvid equipment-tabellen
ALTER TABLE public.equipment
  ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'other'
    CHECK (category IN ('electronics', 'truck', 'machine', 'tool', 'vehicle', 'other')),
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS location TEXT,
  ADD COLUMN IF NOT EXISTS internal_number TEXT,
  ADD COLUMN IF NOT EXISTS license_plate TEXT,
  ADD COLUMN IF NOT EXISTS purchase_date DATE,
  ADD COLUMN IF NOT EXISTS purchase_price NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS warranty_until DATE,
  ADD COLUMN IF NOT EXISTS supplier TEXT,
  ADD COLUMN IF NOT EXISTS receipt_urls TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS responsible_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS registered_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS service_manual_urls TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS next_water_check DATE,
  ADD COLUMN IF NOT EXISTS next_inspection DATE,
  ADD COLUMN IF NOT EXISTS maintenance_interval_days INT DEFAULT 90,
  ADD COLUMN IF NOT EXISTS notify_days_before INT DEFAULT 7,
  ADD COLUMN IF NOT EXISTS notes TEXT,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Service- og vedlikeholdslogg (arkiv)
CREATE TABLE IF NOT EXISTS public.equipment_maintenance_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  equipment_id UUID NOT NULL REFERENCES public.equipment(id) ON DELETE CASCADE,
  maintenance_type TEXT NOT NULL
    CHECK (maintenance_type IN ('service', 'water_fill', 'inspection', 'repair', 'purchase_note', 'other')),
  performed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  performed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  next_due_at DATE,
  cost NUMERIC(12,2),
  odometer_or_hours TEXT,
  notes TEXT,
  document_urls TEXT[] DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_eq_maint_equipment ON public.equipment_maintenance_logs(equipment_id);
CREATE INDEX IF NOT EXISTS idx_eq_maint_company ON public.equipment_maintenance_logs(company_id);
CREATE INDEX IF NOT EXISTS idx_eq_maint_performed ON public.equipment_maintenance_logs(performed_at DESC);

-- Innkjøp / kvitteringer (kan knyttes til utstyr eller stå alene før registrering)
CREATE TABLE IF NOT EXISTS public.equipment_purchases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  equipment_id UUID REFERENCES public.equipment(id) ON DELETE SET NULL,
  item_name TEXT NOT NULL,
  serial_number TEXT,
  purchased_at DATE NOT NULL DEFAULT CURRENT_DATE,
  purchased_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  assigned_to_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  department_id UUID REFERENCES public.departments(id) ON DELETE SET NULL,
  supplier TEXT,
  invoice_number TEXT,
  amount NUMERIC(12,2),
  receipt_urls TEXT[] DEFAULT '{}',
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_eq_purch_company ON public.equipment_purchases(company_id);
CREATE INDEX IF NOT EXISTS idx_eq_purch_equipment ON public.equipment_purchases(equipment_id);

-- Varselinnstillinger per firma (superadmin / admin)
CREATE TABLE IF NOT EXISTS public.equipment_notification_settings (
  company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  notify_responsible BOOLEAN NOT NULL DEFAULT true,
  notify_department_leader BOOLEAN NOT NULL DEFAULT true,
  notify_superadmin BOOLEAN NOT NULL DEFAULT true,
  default_notify_days_before INT NOT NULL DEFAULT 7,
  truck_water_interval_days INT NOT NULL DEFAULT 7,
  truck_service_interval_days INT NOT NULL DEFAULT 90,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);

-- RLS
ALTER TABLE public.equipment_maintenance_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.equipment_purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.equipment_notification_settings ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.current_user_company_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT company_id FROM public.profiles WHERE id = auth.uid();
$$;

DROP POLICY IF EXISTS "eq_maint_company" ON public.equipment_maintenance_logs;
CREATE POLICY "eq_maint_company" ON public.equipment_maintenance_logs
  FOR ALL
  USING (company_id = public.current_user_company_id())
  WITH CHECK (company_id = public.current_user_company_id());

DROP POLICY IF EXISTS "eq_purch_company" ON public.equipment_purchases;
CREATE POLICY "eq_purch_company" ON public.equipment_purchases
  FOR ALL
  USING (company_id = public.current_user_company_id())
  WITH CHECK (company_id = public.current_user_company_id());

DROP POLICY IF EXISTS "eq_notif_company" ON public.equipment_notification_settings;
CREATE POLICY "eq_notif_company" ON public.equipment_notification_settings
  FOR ALL
  USING (company_id = public.current_user_company_id())
  WITH CHECK (company_id = public.current_user_company_id());

-- Oppdater next_service / next_water fra siste logg (valgfritt trigger)
CREATE OR REPLACE FUNCTION public.equipment_after_maintenance_log()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.maintenance_type = 'service' AND NEW.next_due_at IS NOT NULL THEN
    UPDATE public.equipment SET next_service = NEW.next_due_at, last_service = NEW.performed_at::date WHERE id = NEW.equipment_id;
  ELSIF NEW.maintenance_type = 'water_fill' AND NEW.next_due_at IS NOT NULL THEN
    UPDATE public.equipment SET next_water_check = NEW.next_due_at WHERE id = NEW.equipment_id;
  ELSIF NEW.maintenance_type = 'inspection' AND NEW.next_due_at IS NOT NULL THEN
    UPDATE public.equipment SET next_inspection = NEW.next_due_at WHERE id = NEW.equipment_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_equipment_after_maint ON public.equipment_maintenance_logs;
CREATE TRIGGER trg_equipment_after_maint
  AFTER INSERT ON public.equipment_maintenance_logs
  FOR EACH ROW EXECUTE FUNCTION public.equipment_after_maintenance_log();
