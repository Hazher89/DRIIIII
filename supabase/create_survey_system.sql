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

-- 2. Tabell for spørsmål i undersøkelsen
CREATE TABLE IF NOT EXISTS survey_questions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    survey_id UUID NOT NULL REFERENCES surveys(id) ON DELETE CASCADE,
    question_text TEXT NOT NULL,
    question_type TEXT NOT NULL, -- text, paragraph, multiple_choice, checkbox, dropdown, rating, date
    is_required BOOLEAN DEFAULT FALSE,
    options JSONB, -- For valgmuligheter
    order_index INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Tabell for svar-hoder (innleveringer)
CREATE TABLE IF NOT EXISTS survey_responses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    survey_id UUID NOT NULL REFERENCES surveys(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE SET NULL, -- Null hvis anonym
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

-- RLS (Row Level Security)
ALTER TABLE surveys ENABLE ROW LEVEL SECURITY;
ALTER TABLE survey_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE survey_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE survey_answers ENABLE ROW LEVEL SECURITY;

-- Poliser for surveys
CREATE POLICY "Brukere kan se undersøkelser i sitt firma" ON surveys
    FOR SELECT USING (company_id IN (SELECT company_id FROM profiles WHERE id = auth.uid()));

CREATE POLICY "Admin kan administrere undersøkelser" ON surveys
    FOR ALL USING (
        company_id IN (SELECT company_id FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'superadmin'))
    );

-- Poliser for questions
CREATE POLICY "Brukere kan se spørsmål til tilgjengelige undersøkelser" ON survey_questions
    FOR SELECT USING (survey_id IN (SELECT id FROM surveys));

CREATE POLICY "Admin kan administrere spørsmål" ON survey_questions
    FOR ALL USING (
        survey_id IN (SELECT id FROM surveys WHERE company_id IN (SELECT company_id FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'superadmin')))
    );

-- Poliser for responses
CREATE POLICY "Brukere kan sende inn svar" ON survey_responses
    FOR INSERT WITH CHECK (TRUE);

CREATE POLICY "Admin kan se alle svar" ON survey_responses
    FOR SELECT USING (
        survey_id IN (SELECT id FROM surveys WHERE company_id IN (SELECT company_id FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'superadmin')))
    );

-- Poliser for answers
CREATE POLICY "Brukere kan sende inn individuelle svar" ON survey_answers
    FOR INSERT WITH CHECK (TRUE);

CREATE POLICY "Admin kan se alle individuelle svar" ON survey_answers
    FOR SELECT USING (
        response_id IN (SELECT id FROM survey_responses WHERE survey_id IN (SELECT id FROM surveys WHERE company_id IN (SELECT company_id FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'superadmin'))))
    );
