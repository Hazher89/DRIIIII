-- ============================================================
-- DRIFTPRO – ENTERPRISE ERP & HMS PLATFORM
-- Supabase PostgreSQL Schema
-- ============================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- ENUMS
-- ============================================================

CREATE TYPE user_role AS ENUM ('ansatt', 'leder', 'admin', 'superadmin');
CREATE TYPE absence_type AS ENUM ('egenmelding', 'sykt_barn', 'ferie', 'permisjon', 'sykmelding');
CREATE TYPE absence_status AS ENUM ('ventende', 'godkjent', 'avvist');
CREATE TYPE ticket_severity AS ENUM ('lav', 'middels', 'hoy', 'kritisk');
CREATE TYPE ticket_status AS ENUM ('aapen', 'under_behandling', 'tiltak_utfort', 'lukket');
CREATE TYPE risk_probability AS ENUM ('1', '2', '3', '4', '5');
CREATE TYPE risk_consequence AS ENUM ('1', '2', '3', '4', '5');
CREATE TYPE document_type AS ENUM ('kursbevis', 'sertifikat', 'arbeidsavtale', 'hms_dokument', 'annet');
CREATE TYPE notification_type AS ENUM ('push', 'epost', 'begge');
CREATE TYPE sja_status AS ENUM ('utkast', 'signert', 'godkjent', 'avvist');

-- ============================================================
-- COMPANIES (Multi-tenant support)
-- ============================================================

CREATE TABLE companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    org_number TEXT UNIQUE,
    address TEXT,
    logo_url TEXT,
    primary_color TEXT DEFAULT '#1B5E20',
    secondary_color TEXT DEFAULT '#0D47A1',
    max_vacation_carryover INTEGER DEFAULT 14,
    egenmelding_days_per_year INTEGER DEFAULT 24,
    egenmelding_consecutive_max INTEGER DEFAULT 3,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- DEPARTMENTS
-- ============================================================

CREATE TABLE departments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    leader_id UUID, -- FK added after profiles table
    color_code TEXT DEFAULT '#2E7D32',
    icon_name TEXT DEFAULT 'business',
    parent_department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- PROFILES (Users)
-- ============================================================

CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    full_name TEXT NOT NULL,
    role user_role DEFAULT 'ansatt',
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    avatar_url TEXT,
    employee_number TEXT,
    phone TEXT,
    job_title TEXT,
    hire_date DATE,
    birth_date DATE,
    emergency_contact_name TEXT,
    emergency_contact_phone TEXT,
    is_safety_representative BOOLEAN DEFAULT FALSE,
    fcm_token TEXT,
    last_seen_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add FK for department leader
ALTER TABLE departments 
    ADD CONSTRAINT fk_department_leader 
    FOREIGN KEY (leader_id) REFERENCES profiles(id) ON DELETE SET NULL;

-- ============================================================
-- ABSENCES (Fravær)
-- ============================================================

CREATE TABLE absences (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    type absence_type NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    status absence_status DEFAULT 'ventende',
    comment TEXT,
    quota_year INTEGER DEFAULT EXTRACT(YEAR FROM NOW()),
    total_days INTEGER GENERATED ALWAYS AS (end_date - start_date + 1) STORED,
    approved_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
    approved_at TIMESTAMPTZ,
    attachment_urls TEXT[],
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT valid_date_range CHECK (end_date >= start_date)
);

-- ============================================================
-- ABSENCE QUOTAS (Fravær-kvoter)
-- ============================================================

CREATE TABLE absence_quotas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    year INTEGER NOT NULL,
    vacation_days_total INTEGER DEFAULT 25,
    vacation_days_used INTEGER DEFAULT 0,
    vacation_days_carried_over INTEGER DEFAULT 0,
    egenmelding_days_used INTEGER DEFAULT 0,
    egenmelding_periods_used INTEGER DEFAULT 0,
    sykt_barn_days_used INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id, year)
);

-- ============================================================
-- TICKETS (Avvik / Hendelser)
-- ============================================================

CREATE TABLE tickets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    reported_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    assigned_to UUID REFERENCES profiles(id) ON DELETE SET NULL,
    ticket_number SERIAL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT,
    severity ticket_severity DEFAULT 'middels',
    status ticket_status DEFAULT 'aapen',
    image_urls TEXT[],
    annotated_image_urls TEXT[],
    gps_latitude DOUBLE PRECISION,
    gps_longitude DOUBLE PRECISION,
    gps_address TEXT,
    location_description TEXT,
    due_date DATE,
    resolved_at TIMESTAMPTZ,
    resolved_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
    resolution_comment TEXT,
    is_anonymous BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TICKET COMMENTS (Kommentarer / Historikk)
-- ============================================================

CREATE TABLE ticket_comments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ticket_id UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    comment TEXT NOT NULL,
    image_urls TEXT[],
    old_status ticket_status,
    new_status ticket_status,
    is_status_change BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- RISK ASSESSMENTS (Risikoanalyser)
-- ============================================================

CREATE TABLE risk_assessments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    created_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    area TEXT,
    probability INTEGER NOT NULL CHECK (probability BETWEEN 1 AND 5),
    consequence INTEGER NOT NULL CHECK (consequence BETWEEN 1 AND 5),
    risk_score INTEGER GENERATED ALWAYS AS (probability * consequence) STORED,
    existing_measures TEXT,
    proposed_measures TEXT,
    responsible_person UUID REFERENCES profiles(id) ON DELETE SET NULL,
    image_urls TEXT[],
    status TEXT DEFAULT 'aktiv',
    review_date DATE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- SJA (Sikker Jobb Analyse)
-- ============================================================

CREATE TABLE sja_forms (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    created_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    work_description TEXT NOT NULL,
    location TEXT,
    planned_date DATE NOT NULL,
    status sja_status DEFAULT 'utkast',
    hazards JSONB DEFAULT '[]'::JSONB,
    measures JSONB DEFAULT '[]'::JSONB,
    required_ppe TEXT[],
    signed_by UUID[] DEFAULT '{}',
    signature_urls TEXT[],
    approved_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- DOCUMENTS (Personalmappe / Dokumenter)
-- ============================================================

CREATE TABLE documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    document_type document_type NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    file_url TEXT NOT NULL,
    file_name TEXT,
    file_size INTEGER,
    expires_at DATE,
    is_verified BOOLEAN DEFAULT FALSE,
    verified_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
    uploaded_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- SAFETY ROUNDS (Sikkerhetsrunder / Vernerunder)
-- ============================================================

CREATE TABLE safety_rounds (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    conducted_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    checklist JSONB DEFAULT '[]'::JSONB,
    findings JSONB DEFAULT '[]'::JSONB,
    overall_status TEXT DEFAULT 'planlagt',
    scheduled_date DATE,
    completed_at TIMESTAMPTZ,
    next_round_date DATE,
    image_urls TEXT[],
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- NOTIFICATIONS (Varsler)
-- ============================================================

CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    type notification_type DEFAULT 'push',
    data JSONB DEFAULT '{}'::JSONB,
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- AUDIT LOG (Revisjonslogg)
-- ============================================================

CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    table_name TEXT NOT NULL,
    record_id UUID,
    old_data JSONB,
    new_data JSONB,
    ip_address TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX idx_profiles_company ON profiles(company_id);
CREATE INDEX idx_profiles_department ON profiles(department_id);
CREATE INDEX idx_profiles_role ON profiles(role);

CREATE INDEX idx_absences_user ON absences(user_id);
CREATE INDEX idx_absences_dates ON absences(start_date, end_date);
CREATE INDEX idx_absences_company ON absences(company_id);
CREATE INDEX idx_absences_status ON absences(status);

CREATE INDEX idx_tickets_company ON tickets(company_id);
CREATE INDEX idx_tickets_department ON tickets(department_id);
CREATE INDEX idx_tickets_status ON tickets(status);
CREATE INDEX idx_tickets_severity ON tickets(severity);
CREATE INDEX idx_tickets_reported_by ON tickets(reported_by);

CREATE INDEX idx_risk_assessments_company ON risk_assessments(company_id);
CREATE INDEX idx_risk_assessments_score ON risk_assessments(probability, consequence);

CREATE INDEX idx_documents_user ON documents(user_id);
CREATE INDEX idx_documents_expires ON documents(expires_at);

CREATE INDEX idx_notifications_user ON notifications(user_id);
CREATE INDEX idx_notifications_read ON notifications(is_read);

CREATE INDEX idx_audit_log_company ON audit_log(company_id);
CREATE INDEX idx_audit_log_action ON audit_log(action);

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================

ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE absences ENABLE ROW LEVEL SECURITY;
ALTER TABLE absence_quotas ENABLE ROW LEVEL SECURITY;
ALTER TABLE tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE ticket_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE risk_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE sja_forms ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE safety_rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

-- Helper function: Get user's company_id
CREATE OR REPLACE FUNCTION get_user_company_id()
RETURNS UUID AS $$
    SELECT company_id FROM profiles WHERE id = auth.uid();
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- Helper function: Get user's role
CREATE OR REPLACE FUNCTION get_user_role()
RETURNS user_role AS $$
    SELECT role FROM profiles WHERE id = auth.uid();
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- Helper function: Get user's department_id
CREATE OR REPLACE FUNCTION get_user_department_id()
RETURNS UUID AS $$
    SELECT department_id FROM profiles WHERE id = auth.uid();
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- Helper function: Check if user is leader of a department
CREATE OR REPLACE FUNCTION is_department_leader(dept_id UUID)
RETURNS BOOLEAN AS $$
    SELECT EXISTS(
        SELECT 1 FROM departments 
        WHERE id = dept_id AND leader_id = auth.uid()
    );
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- ---- PROFILES POLICIES ----
CREATE POLICY "Brukere kan se profiler i eget selskap"
    ON profiles FOR SELECT
    USING (company_id = get_user_company_id());

CREATE POLICY "Brukere kan oppdatere egen profil"
    ON profiles FOR UPDATE
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

CREATE POLICY "Admin kan oppdatere alle profiler i selskapet"
    ON profiles FOR UPDATE
    USING (
        company_id = get_user_company_id() 
        AND get_user_role() IN ('admin', 'superadmin')
    );

CREATE POLICY "Admin kan sette inn nye profiler"
    ON profiles FOR INSERT
    WITH CHECK (
        company_id = get_user_company_id() 
        AND get_user_role() IN ('admin', 'superadmin')
    );

-- ---- DEPARTMENTS POLICIES ----
CREATE POLICY "Ansatte kan se avdelinger i eget selskap"
    ON departments FOR SELECT
    USING (company_id = get_user_company_id());

CREATE POLICY "Admin kan administrere avdelinger"
    ON departments FOR ALL
    USING (
        company_id = get_user_company_id() 
        AND get_user_role() IN ('admin', 'superadmin')
    );

-- ---- ABSENCES POLICIES ----
CREATE POLICY "Ansatte kan se eget fravær"
    ON absences FOR SELECT
    USING (user_id = auth.uid());

CREATE POLICY "Ledere kan se fravær i sin avdeling"
    ON absences FOR SELECT
    USING (
        department_id = get_user_department_id()
        AND get_user_role() IN ('leder', 'admin', 'superadmin')
    );

CREATE POLICY "Admin kan se alt fravær i selskapet"
    ON absences FOR SELECT
    USING (
        company_id = get_user_company_id()
        AND get_user_role() IN ('admin', 'superadmin')
    );

CREATE POLICY "Ansatte kan registrere eget fravær"
    ON absences FOR INSERT
    WITH CHECK (user_id = auth.uid() AND company_id = get_user_company_id());

CREATE POLICY "Ledere kan godkjenne fravær i sin avdeling"
    ON absences FOR UPDATE
    USING (
        department_id = get_user_department_id()
        AND get_user_role() IN ('leder', 'admin', 'superadmin')
    );

-- ---- TICKETS POLICIES ----
CREATE POLICY "Ansatte kan se avvik i sin avdeling"
    ON tickets FOR SELECT
    USING (
        company_id = get_user_company_id()
        AND (
            reported_by = auth.uid()
            OR department_id = get_user_department_id()
            OR get_user_role() IN ('admin', 'superadmin')
        )
    );

CREATE POLICY "Ansatte kan opprette avvik"
    ON tickets FOR INSERT
    WITH CHECK (company_id = get_user_company_id());

CREATE POLICY "Ledere kan oppdatere avvik i sin avdeling"
    ON tickets FOR UPDATE
    USING (
        company_id = get_user_company_id()
        AND (
            reported_by = auth.uid()
            OR is_department_leader(department_id)
            OR get_user_role() IN ('admin', 'superadmin')
        )
    );

-- ---- RISK ASSESSMENTS POLICIES ----
CREATE POLICY "Ansatte kan se risikoanalyser i sitt selskap"
    ON risk_assessments FOR SELECT
    USING (company_id = get_user_company_id());

CREATE POLICY "Ledere kan opprette risikoanalyser"
    ON risk_assessments FOR INSERT
    WITH CHECK (
        company_id = get_user_company_id()
        AND get_user_role() IN ('leder', 'admin', 'superadmin')
    );

CREATE POLICY "Ledere kan oppdatere risikoanalyser"
    ON risk_assessments FOR UPDATE
    USING (
        company_id = get_user_company_id()
        AND (
            created_by = auth.uid()
            OR get_user_role() IN ('admin', 'superadmin')
        )
    );

-- ---- SJA FORMS POLICIES ----
CREATE POLICY "Ansatte kan se SJA i sitt selskap"
    ON sja_forms FOR SELECT
    USING (company_id = get_user_company_id());

CREATE POLICY "Alle kan opprette SJA"
    ON sja_forms FOR INSERT
    WITH CHECK (company_id = get_user_company_id());

CREATE POLICY "Opprettere og ledere kan oppdatere SJA"
    ON sja_forms FOR UPDATE
    USING (
        company_id = get_user_company_id()
        AND (
            created_by = auth.uid()
            OR get_user_role() IN ('leder', 'admin', 'superadmin')
        )
    );

-- ---- DOCUMENTS POLICIES ----
CREATE POLICY "Ansatte kan se egne dokumenter"
    ON documents FOR SELECT
    USING (user_id = auth.uid());

CREATE POLICY "Ledere kan se dokumenter i sin avdeling"
    ON documents FOR SELECT
    USING (
        company_id = get_user_company_id()
        AND get_user_role() IN ('leder', 'admin', 'superadmin')
    );

CREATE POLICY "Ansatte kan laste opp egne dokumenter"
    ON documents FOR INSERT
    WITH CHECK (
        user_id = auth.uid() 
        AND company_id = get_user_company_id()
    );

-- ---- NOTIFICATIONS POLICIES ----
CREATE POLICY "Brukere kan kun se egne varsler"
    ON notifications FOR SELECT
    USING (user_id = auth.uid());

CREATE POLICY "Brukere kan oppdatere egne varsler"
    ON notifications FOR UPDATE
    USING (user_id = auth.uid());

-- ---- SAFETY ROUNDS POLICIES ----
CREATE POLICY "Ansatte kan se sikkerhetsrunder i sitt selskap"
    ON safety_rounds FOR SELECT
    USING (company_id = get_user_company_id());

CREATE POLICY "Ledere kan opprette sikkerhetsrunder"
    ON safety_rounds FOR INSERT
    WITH CHECK (
        company_id = get_user_company_id()
        AND get_user_role() IN ('leder', 'admin', 'superadmin')
    );

-- ---- TICKET COMMENTS POLICIES ----
CREATE POLICY "Brukere kan se kommentarer på tilgjengelige avvik"
    ON ticket_comments FOR SELECT
    USING (
        EXISTS(
            SELECT 1 FROM tickets t 
            WHERE t.id = ticket_id 
            AND t.company_id = get_user_company_id()
        )
    );

CREATE POLICY "Brukere kan kommentere på avvik"
    ON ticket_comments FOR INSERT
    WITH CHECK (
        EXISTS(
            SELECT 1 FROM tickets t 
            WHERE t.id = ticket_id 
            AND t.company_id = get_user_company_id()
        )
    );

-- ---- ABSENCE QUOTAS POLICIES ----
CREATE POLICY "Ansatte kan se egne kvoter"
    ON absence_quotas FOR SELECT
    USING (user_id = auth.uid());

CREATE POLICY "Admin kan se alle kvoter i selskapet"
    ON absence_quotas FOR SELECT
    USING (
        company_id = get_user_company_id()
        AND get_user_role() IN ('admin', 'superadmin')
    );

-- ---- AUDIT LOG POLICIES ----
CREATE POLICY "Admin kan se revisjonslogg"
    ON audit_log FOR SELECT
    USING (
        company_id = get_user_company_id()
        AND get_user_role() IN ('admin', 'superadmin')
    );

-- ============================================================
-- FUNCTIONS
-- ============================================================

-- Function: Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to all relevant tables
DO $$
DECLARE
    t TEXT;
BEGIN
    FOR t IN 
        SELECT unnest(ARRAY[
            'companies', 'departments', 'profiles', 'absences', 
            'absence_quotas', 'tickets', 'risk_assessments', 
            'sja_forms', 'documents', 'safety_rounds'
        ])
    LOOP
        EXECUTE format(
            'CREATE TRIGGER update_%I_updated_at 
             BEFORE UPDATE ON %I 
             FOR EACH ROW EXECUTE FUNCTION update_updated_at_column()',
            t, t
        );
    END LOOP;
END;
$$;

-- Function: Validate egenmelding rules
CREATE OR REPLACE FUNCTION validate_egenmelding()
RETURNS TRIGGER AS $$
DECLARE
    _quota absence_quotas%ROWTYPE;
    _company companies%ROWTYPE;
    _days INTEGER;
BEGIN
    IF NEW.type != 'egenmelding' THEN
        RETURN NEW;
    END IF;
    
    _days := NEW.end_date - NEW.start_date + 1;
    
    -- Get company settings
    SELECT * INTO _company FROM companies WHERE id = NEW.company_id;
    
    -- Check consecutive days (max 3 by law, configurable)
    IF _days > _company.egenmelding_consecutive_max THEN
        RAISE EXCEPTION 'Egenmelding kan ikke overstige % sammenhengende dager', 
            _company.egenmelding_consecutive_max;
    END IF;
    
    -- Get or create quota for current year
    SELECT * INTO _quota FROM absence_quotas 
    WHERE user_id = NEW.user_id AND year = EXTRACT(YEAR FROM NEW.start_date);
    
    IF _quota IS NULL THEN
        INSERT INTO absence_quotas (user_id, company_id, year)
        VALUES (NEW.user_id, NEW.company_id, EXTRACT(YEAR FROM NEW.start_date))
        RETURNING * INTO _quota;
    END IF;
    
    -- Check annual limit
    IF (_quota.egenmelding_days_used + _days) > _company.egenmelding_days_per_year THEN
        RAISE EXCEPTION 'Egenmeldingskvoten for året er brukt opp (% av % dager brukt)',
            _quota.egenmelding_days_used, _company.egenmelding_days_per_year;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER validate_egenmelding_trigger
    BEFORE INSERT ON absences
    FOR EACH ROW EXECUTE FUNCTION validate_egenmelding();

-- Function: Update quota on absence approval
CREATE OR REPLACE FUNCTION update_absence_quota()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'godkjent' AND (OLD.status IS NULL OR OLD.status != 'godkjent') THEN
        -- Update relevant quota
        IF NEW.type = 'egenmelding' THEN
            UPDATE absence_quotas 
            SET egenmelding_days_used = egenmelding_days_used + NEW.total_days,
                egenmelding_periods_used = egenmelding_periods_used + 1
            WHERE user_id = NEW.user_id AND year = NEW.quota_year;
        ELSIF NEW.type = 'ferie' THEN
            UPDATE absence_quotas 
            SET vacation_days_used = vacation_days_used + NEW.total_days
            WHERE user_id = NEW.user_id AND year = NEW.quota_year;
        ELSIF NEW.type = 'sykt_barn' THEN
            UPDATE absence_quotas 
            SET sykt_barn_days_used = sykt_barn_days_used + NEW.total_days
            WHERE user_id = NEW.user_id AND year = NEW.quota_year;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER update_quota_on_approval
    AFTER UPDATE ON absences
    FOR EACH ROW EXECUTE FUNCTION update_absence_quota();

-- Function: Create audit log entry
CREATE OR REPLACE FUNCTION create_audit_log()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (company_id, user_id, action, table_name, record_id, old_data, new_data)
    VALUES (
        COALESCE(NEW.company_id, OLD.company_id),
        auth.uid(),
        TG_OP,
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) ELSE NULL END
    );
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Apply audit triggers to critical tables
DO $$
DECLARE
    t TEXT;
BEGIN
    FOR t IN 
        SELECT unnest(ARRAY['tickets', 'risk_assessments', 'sja_forms', 'absences'])
    LOOP
        EXECUTE format(
            'CREATE TRIGGER audit_%I 
             AFTER INSERT OR UPDATE OR DELETE ON %I 
             FOR EACH ROW EXECUTE FUNCTION create_audit_log()',
            t, t
        );
    END LOOP;
END;
$$;

-- Function: Annual vacation carryover (Run as cron on Jan 1)
CREATE OR REPLACE FUNCTION annual_vacation_carryover()
RETURNS VOID AS $$
DECLARE
    _profile RECORD;
    _quota absence_quotas%ROWTYPE;
    _company companies%ROWTYPE;
    _remaining INTEGER;
    _carryover INTEGER;
    _new_year INTEGER := EXTRACT(YEAR FROM NOW());
    _old_year INTEGER := _new_year - 1;
BEGIN
    FOR _profile IN SELECT * FROM profiles WHERE is_active = TRUE LOOP
        -- Get last year's quota
        SELECT * INTO _quota FROM absence_quotas 
        WHERE user_id = _profile.id AND year = _old_year;
        
        IF _quota IS NOT NULL THEN
            SELECT * INTO _company FROM companies WHERE id = _profile.company_id;
            
            _remaining := (_quota.vacation_days_total + _quota.vacation_days_carried_over) - _quota.vacation_days_used;
            _carryover := LEAST(_remaining, _company.max_vacation_carryover);
            
            IF _carryover < 0 THEN _carryover := 0; END IF;
            
            -- Create new year quota with carryover
            INSERT INTO absence_quotas (user_id, company_id, year, vacation_days_carried_over)
            VALUES (_profile.id, _profile.company_id, _new_year, _carryover)
            ON CONFLICT (user_id, year) 
            DO UPDATE SET vacation_days_carried_over = _carryover;
        ELSE
            -- Create fresh quota
            INSERT INTO absence_quotas (user_id, company_id, year)
            VALUES (_profile.id, _profile.company_id, _new_year)
            ON CONFLICT (user_id, year) DO NOTHING;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Dashboard statistics RPC
CREATE OR REPLACE FUNCTION get_dashboard_stats(p_company_id UUID)
RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'today_absences', (
            SELECT COUNT(*) FROM absences 
            WHERE company_id = p_company_id 
            AND CURRENT_DATE BETWEEN start_date AND end_date
            AND status = 'godkjent'
        ),
        'open_tickets', (
            SELECT COUNT(*) FROM tickets 
            WHERE company_id = p_company_id 
            AND status IN ('aapen', 'under_behandling')
        ),
        'critical_tickets', (
            SELECT COUNT(*) FROM tickets 
            WHERE company_id = p_company_id 
            AND severity = 'kritisk' 
            AND status != 'lukket'
        ),
        'high_risk_count', (
            SELECT COUNT(*) FROM risk_assessments 
            WHERE company_id = p_company_id 
            AND (probability * consequence) >= 15
            AND status = 'aktiv'
        ),
        'pending_sja', (
            SELECT COUNT(*) FROM sja_forms 
            WHERE company_id = p_company_id 
            AND status = 'utkast'
        ),
        'expiring_documents', (
            SELECT COUNT(*) FROM documents 
            WHERE company_id = p_company_id 
            AND expires_at BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'
        ),
        'upcoming_safety_rounds', (
            SELECT COUNT(*) FROM safety_rounds 
            WHERE company_id = p_company_id 
            AND scheduled_date >= CURRENT_DATE 
            AND overall_status = 'planlagt'
        ),
        'total_employees', (
            SELECT COUNT(*) FROM profiles 
            WHERE company_id = p_company_id AND is_active = TRUE
        ),
        'absence_rate', (
            SELECT ROUND(
                (COUNT(*) FILTER (
                    WHERE CURRENT_DATE BETWEEN start_date AND end_date 
                    AND status = 'godkjent'
                )::DECIMAL / 
                GREATEST((SELECT COUNT(*) FROM profiles WHERE company_id = p_company_id AND is_active = TRUE), 1)) * 100, 
                1
            ) FROM absences WHERE company_id = p_company_id
        )
    ) INTO result;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Notify safety representative on high risk
CREATE OR REPLACE FUNCTION notify_high_risk()
RETURNS TRIGGER AS $$
DECLARE
    _risk_score INTEGER;
    _safety_rep RECORD;
BEGIN
    _risk_score := NEW.probability * NEW.consequence;
    
    IF _risk_score >= 15 THEN
        FOR _safety_rep IN 
            SELECT id FROM profiles 
            WHERE company_id = NEW.company_id 
            AND is_safety_representative = TRUE 
            AND is_active = TRUE
        LOOP
            INSERT INTO notifications (user_id, company_id, title, body, type, data)
            VALUES (
                _safety_rep.id,
                NEW.company_id,
                'Høyrisiko-funn registrert',
                format('Risikoanalyse "%s" har fått score %s (Høy risiko)', NEW.title, _risk_score),
                'begge',
                jsonb_build_object('risk_assessment_id', NEW.id, 'score', _risk_score)
            );
        END LOOP;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER notify_on_high_risk
    AFTER INSERT OR UPDATE ON risk_assessments
    FOR EACH ROW EXECUTE FUNCTION notify_high_risk();

-- ============================================================
-- STORAGE BUCKETS
-- ============================================================

-- Note: Run these in Supabase Dashboard or via API
-- INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true);
-- INSERT INTO storage.buckets (id, name, public) VALUES ('tickets', 'tickets', false);
-- INSERT INTO storage.buckets (id, name, public) VALUES ('documents', 'documents', false);
-- INSERT INTO storage.buckets (id, name, public) VALUES ('sja', 'sja', false);
-- INSERT INTO storage.buckets (id, name, public) VALUES ('risk-assessments', 'risk-assessments', false);

-- ============================================================
-- SEED DATA (Optional: Demo company)
-- ============================================================

-- INSERT INTO companies (name, org_number) 
-- VALUES ('DriftPro Demo AS', '123456789');
