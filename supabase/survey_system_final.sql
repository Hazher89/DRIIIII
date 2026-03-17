-- CLEANUP (Optional, use with caution if you want to reset)
-- DROP TABLE IF EXISTS survey_answers CASCADE;
-- DROP TABLE IF EXISTS survey_responses CASCADE;
-- DROP TABLE IF EXISTS survey_questions CASCADE;
-- DROP TABLE IF EXISTS surveys CASCADE;

-- 1. Tabell for undersøkelser
CREATE TABLE IF NOT EXISTS surveys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    created_by UUID NOT NULL REFERENCES profiles(id),
    is_active BOOLEAN DEFAULT TRUE,
    allow_anonymous BOOLEAN DEFAULT TRUE,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Tabell for spørsmål
CREATE TABLE IF NOT EXISTS survey_questions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    survey_id UUID NOT NULL REFERENCES surveys(id) ON DELETE CASCADE,
    question_text TEXT NOT NULL,
    question_type TEXT NOT NULL, 
    is_required BOOLEAN DEFAULT FALSE,
    options JSONB DEFAULT '[]'::jsonb, 
    order_index INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Tabell for svar (innleveringer)
CREATE TABLE IF NOT EXISTS survey_responses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    survey_id UUID NOT NULL REFERENCES surveys(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    submitted_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

-- 4. Tabell for individuelle svar
CREATE TABLE IF NOT EXISTS survey_answers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    response_id UUID NOT NULL REFERENCES survey_responses(id) ON DELETE CASCADE,
    question_id UUID NOT NULL REFERENCES survey_questions(id) ON DELETE CASCADE,
    answer_value JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ENABLE RLS
ALTER TABLE surveys ENABLE ROW LEVEL SECURITY;
ALTER TABLE survey_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE survey_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE survey_answers ENABLE ROW LEVEL SECURITY;

-- POLICIES
-- Surveys
DROP POLICY IF EXISTS "Brukere kan se undersøkelser i sitt firma" ON surveys;
CREATE POLICY "Brukere kan se undersøkelser i sitt firma" ON surveys
    FOR SELECT USING (company_id IN (SELECT company_id FROM profiles WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Admin kan administrere undersøkelser" ON surveys;
CREATE POLICY "Admin kan administrere undersøkelser" ON surveys
    FOR ALL USING (
        company_id IN (SELECT company_id FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'superadmin'))
    );

-- Questions
DROP POLICY IF EXISTS "Brukere kan se spørsmål" ON survey_questions;
CREATE POLICY "Brukere kan se spørsmål" ON survey_questions
    FOR SELECT USING (TRUE); -- Allow everyone to see questions (needed for public surveys)

DROP POLICY IF EXISTS "Admin kan administrere spørsmål" ON survey_questions;
CREATE POLICY "Admin kan administrere spørsmål" ON survey_questions
    FOR ALL USING (
        survey_id IN (SELECT id FROM surveys WHERE company_id IN (SELECT company_id FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'superadmin')))
    );

-- Responses
DROP POLICY IF EXISTS "Alle kan sende svar" ON survey_responses;
CREATE POLICY "Alle kan sende svar" ON survey_responses
    FOR INSERT WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Admin kan se svar" ON survey_responses;
CREATE POLICY "Admin kan se svar" ON survey_responses
    FOR SELECT USING (
        survey_id IN (SELECT id FROM surveys WHERE company_id IN (SELECT company_id FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'superadmin')))
    );

-- Answers
DROP POLICY IF EXISTS "Alle kan sende individuelle svar" ON survey_answers;
CREATE POLICY "Alle kan sende individuelle svar" ON survey_answers
    FOR INSERT WITH CHECK (TRUE);

DROP POLICY IF EXISTS "Admin kan se individuelle svar" ON survey_answers;
CREATE POLICY "Admin kan se individuelle svar" ON survey_answers
    FOR SELECT USING (
        response_id IN (SELECT id FROM survey_responses WHERE survey_id IN (SELECT id FROM surveys WHERE company_id IN (SELECT company_id FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'superadmin'))))
    );
