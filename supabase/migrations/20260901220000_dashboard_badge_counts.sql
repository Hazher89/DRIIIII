-- Badge-tall: ekskluder slettede avvik og tell kun åpne HMS-oppgaver.

CREATE OR REPLACE FUNCTION public.get_dashboard_stats(p_company_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
              AND deleted_at IS NULL
              AND status IN ('aapen', 'under_behandling')
        ),
        'critical_tickets', (
            SELECT COUNT(*) FROM tickets
            WHERE company_id = p_company_id
              AND deleted_at IS NULL
              AND severity = 'kritisk'
              AND status != 'lukket'
        ),
        'open_risk_count', (
            SELECT COUNT(*) FROM risk_assessments
            WHERE company_id = p_company_id
              AND status IN ('aktiv', 'under_behandling', 'utkast')
        ),
        'high_risk_count', (
            SELECT COUNT(*) FROM risk_assessments
            WHERE company_id = p_company_id
              AND (probability * consequence) >= 15
              AND status IN ('aktiv', 'under_behandling', 'utkast')
        ),
        'pending_sja', (
            SELECT COUNT(*) FROM sja_forms
            WHERE company_id = p_company_id
              AND status IN ('utkast', 'venter_signatur', 'i_gang')
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
$$;
