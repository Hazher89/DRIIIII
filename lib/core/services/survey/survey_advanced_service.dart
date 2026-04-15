import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/survey/survey.dart';
import '../../../models/survey/survey_advanced.dart';

class SurveyAdvancedService {
  static final SupabaseClient _client = Supabase.instance.client;

  static Future<SurveyThemeConfig> fetchTheme(String surveyId) async {
    final row = await _client
        .from('survey_theme_configs')
        .select()
        .eq('survey_id', surveyId)
        .maybeSingle();

    if (row == null) {
      return SurveyThemeConfig(surveyId: surveyId);
    }
    return SurveyThemeConfig.fromJson(row);
  }

  static Future<void> upsertTheme(SurveyThemeConfig theme) async {
    await _client.from('survey_theme_configs').upsert(theme.toJson());
  }

  static Future<List<SurveyArchiveEntry>> fetchArchive({
    required String companyId,
  }) async {
    final rows = await _client
        .from('survey_archive_entries')
        .select()
        .eq('company_id', companyId)
        .order('archived_at', ascending: false);

    return (rows as List)
        .map((e) => SurveyArchiveEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> archiveSurvey({
    required Survey survey,
    required String archivedBy,
    String? note,
  }) async {
    await _client.from('survey_archive_entries').insert({
      'survey_id': survey.id,
      'company_id': survey.companyId,
      'title': survey.title,
      'status': survey.isActive ? 'closed' : 'archived',
      'archived_by': archivedBy,
      'responses_at_archive': survey.totalResponses,
      'note': note,
    });

    await _client
        .from('surveys')
        .update({'is_active': false}).eq('id', survey.id);
  }

  static Future<List<SurveyAnalyticsSnapshot>> fetchSnapshots(
    String surveyId,
  ) async {
    final rows = await _client
        .from('survey_analytics_snapshots')
        .select()
        .eq('survey_id', surveyId)
        .order('generated_at', ascending: false)
        .limit(10);

    return (rows as List)
        .map((e) => SurveyAnalyticsSnapshot.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

