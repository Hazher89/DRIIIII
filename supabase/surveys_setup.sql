-- ============================================================
-- SURVEY SYSTEM (Undersøkelser)
-- ============================================================

-- Types
CREATE TYPE survey_question_type AS ENUM ('text', 'paragraph', 'multiple_choice', 'checkbox', 'dropdown', 'rating', 'date');

-- Surveys Table
CREATE TABLE surveys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    created_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    is_active BOOLEAN DEFAULT TRUE,
    allow_anonymous BOOLEAN DEFAULT TRUE,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Questions Table
CREATE TABLE survey_questions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    survey_id UUID NOT NULL REFERENCES surveys(id) ON DELETE CASCADE,
    question_text TEXT NOT NULL,
    question_type survey_question_type NOT NULL,
    is_required BOOLEAN DEFAULT FALSE,
    options JSONB DEFAULT '[]'::JSONB, -- For multiple choice, etc.
    order_index INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Responses Table
CREATE TABLE survey_responses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    survey_id UUID NOT NULL REFERENCES surveys(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE SET NULL, -- Null if anonymous
    submitted_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::JSONB -- IP, browser, etc.
);

-- Answers Table
CREATE TABLE survey_answers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    response_id UUID NOT NULL REFERENCES survey_responses(id) ON DELETE CASCADE,
    question_id UUID NOT NULL REFERENCES survey_questions(id) ON DELETE CASCADE,
    answer_value JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE surveys ENABLE ROW LEVEL SECURITY;
ALTER TABLE survey_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE survey_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE survey_answers ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can see surveys in their company"
    ON surveys FOR SELECT
    USING (company_id = get_user_company_id());

CREATE POLICY "Admins can manage surveys"
    ON surveys FOR ALL
    USING (
        company_id = get_user_company_id() 
        AND get_user_role() IN ('leder', 'admin', 'superadmin')
    );

CREATE POLICY "Public/Users can see questions of active surveys"
    ON survey_questions FOR SELECT
    USING (EXISTS (SELECT 1 FROM surveys s WHERE s.id = survey_id AND (s.is_active = TRUE OR s.company_id = get_user_company_id())));

CREATE POLICY "Admins can manage questions"
    ON survey_questions FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM surveys s 
            WHERE s.id = survey_id 
            AND s.company_id = get_user_company_id() 
            AND get_user_role() IN ('leder', 'admin', 'superadmin')
        )
    );

CREATE POLICY "Everyone can insert responses"
    ON survey_responses FOR INSERT
    WITH CHECK (TRUE); -- Usually validated by logic/survey existence

CREATE POLICY "Admins can see responses"
    ON survey_responses FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM surveys s 
            WHERE s.id = survey_id 
            AND s.company_id = get_user_company_id() 
            AND (s.created_by = auth.uid() OR get_user_role() IN ('admin', 'superadmin'))
        )
    );

CREATE POLICY "Everyone can insert answers"
    ON survey_answers FOR INSERT
    WITH CHECK (TRUE);

CREATE POLICY "Admins can see answers"
    ON survey_answers FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM survey_responses r
            JOIN surveys s ON s.id = r.survey_id
            WHERE r.id = response_id
            AND s.company_id = get_user_company_id()
            AND (s.created_by = auth.uid() OR get_user_role() IN ('admin', 'superadmin'))
        )
    );

-- Indexes
CREATE INDEX idx_surveys_company ON surveys(company_id);
CREATE INDEX idx_survey_questions_survey ON survey_questions(survey_id);
CREATE INDEX idx_survey_responses_survey ON survey_responses(survey_id);
CREATE INDEX idx_survey_answers_response ON survey_answers(response_id);
