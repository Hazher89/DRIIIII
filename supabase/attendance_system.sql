-- Create attendance_status enum
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'attendance_status') THEN
        CREATE TYPE attendance_status AS ENUM ('on_duty', 'off_duty');
    END IF;
END $$;

-- Create employee_attendance table
CREATE TABLE IF NOT EXISTS employee_attendance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) NOT NULL,
    company_id UUID REFERENCES companies(id),
    status attendance_status NOT NULL DEFAULT 'off_duty',
    check_in_at TIMESTAMPTZ,
    check_out_at TIMESTAMPTZ,
    last_updated TIMESTAMPTZ DEFAULT now(),
    
    UNIQUE(user_id)
);

-- Enable RLS
ALTER TABLE employee_attendance ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Employees can see their own attendance"
    ON employee_attendance FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "All employees can see on_duty status in same company"
    ON employee_attendance FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE profiles.id = auth.uid() 
            AND profiles.company_id = employee_attendance.company_id
        )
    );

CREATE POLICY "Employees can upsert their own attendance"
    ON employee_attendance FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Employees can update their own status"
    ON employee_attendance FOR UPDATE
    USING (auth.uid() = user_id);

-- Log table for history
CREATE TABLE IF NOT EXISTS attendance_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) NOT NULL,
    company_id UUID REFERENCES companies(id),
    action attendance_status NOT NULL,
    timestamp TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE attendance_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Employees can see their own logs"
    ON attendance_logs FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Admins can see all logs for their company"
    ON attendance_logs FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE profiles.id = auth.uid() 
            AND (profiles.role = 'admin' OR profiles.role = 'superadmin' OR profiles.role = 'leder')
            AND profiles.company_id = attendance_logs.company_id
        )
    );
