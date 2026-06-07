import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/survey/survey.dart';

class SurveyService {
  static final _supabase = Supabase.instance.client;

  static Future<List<Survey>> fetchSurveys({required String companyId}) async {
    final response = await _supabase
        .from('surveys')
        .select('*, survey_responses(id)')
        .eq('company_id', companyId)
        .order('created_at', ascending: false);
    
    return List<Survey>.from(response.map((x) => Survey.fromJson(x)));
  }

  static Future<Survey> createSurvey({
    required String companyId,
    required String title,
    String? description,
    required String createdBy,
    bool allowAnonymous = true,
  }) async {
    final response = await _supabase
        .from('surveys')
        .insert({
          'company_id': companyId,
          'title': title,
          'description': description,
          'created_by': createdBy,
          'allow_anonymous': allowAnonymous,
        })
        .select()
        .single();
    
    return Survey.fromJson(response);
  }

  static Future<void> updateSurvey({
    required String id,
    String? title,
    String? description,
    bool? allowAnonymous,
    bool? isActive,
    String? theme,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
  }) async {
    final Map<String, dynamic> data = {};
    if (title != null) data['title'] = title;
    if (description != null) data['description'] = description;
    if (allowAnonymous != null) data['allow_anonymous'] = allowAnonymous;
    if (isActive != null) data['is_active'] = isActive;
    if (theme != null) data['theme'] = theme;
    if (clearExpiresAt) {
      data['expires_at'] = null;
    } else if (expiresAt != null) {
      data['expires_at'] = expiresAt.toIso8601String();
    }

    if (data.isNotEmpty) {
      await _supabase.from('surveys').update(data).eq('id', id);
    }
  }

  static Future<Survey> fetchSurveyById(String id) async {
    final response = await _supabase
        .from('surveys')
        .select('*, survey_responses(id)')
        .eq('id', id)
        .single();
    return Survey.fromJson(response);
  }

  static Future<Survey> duplicateSurvey({
    required Survey source,
    required String createdBy,
  }) async {
    final copy = await _supabase
        .from('surveys')
        .insert({
          'company_id': source.companyId,
          'title': '${source.title} (kopi)',
          'description': source.description,
          'created_by': createdBy,
          'allow_anonymous': source.allowAnonymous,
          'theme': source.theme,
          'is_active': false,
        })
        .select()
        .single();

    final newId = copy['id'] as String;
    final questions = await fetchQuestions(source.id);
    if (questions.isNotEmpty) {
      await _supabase.from('survey_questions').insert(
            questions.map((q) => {
                  'survey_id': newId,
                  'question_text': q.questionText,
                  'question_type': q.type.toIdentifier(),
                  'is_required': q.isRequired,
                  'options': q.options,
                  'order_index': q.orderIndex,
                  'section_title': q.sectionTitle,
                  'points': q.points,
                  'condition_question_id': q.conditionQuestionId,
                  'condition_operator': q.conditionOperator,
                  'condition_value': q.conditionValue,
                }),
          );
    }
    return Survey.fromJson(copy);
  }

  static Future<void> deleteSurvey(String id) async {
    await _supabase.from('surveys').delete().eq('id', id);
  }

  static Future<List<SurveyQuestion>> fetchQuestions(String surveyId) async {
    final response = await _supabase
        .from('survey_questions')
        .select()
        .eq('survey_id', surveyId)
        .order('order_index', ascending: true);
    
    return List<SurveyQuestion>.from(response.map((x) => SurveyQuestion.fromJson(x)));
  }

  static Future<List<SurveyQuestion>> saveQuestions(String surveyId, List<SurveyQuestion> questions) async {
    if (questions.isEmpty) {
      await _supabase.from('survey_questions').delete().eq('survey_id', surveyId);
      return [];
    }

    // 1. Map questions to DB format, including IDs if they exist
    final data = questions.map((q) {
      final map = {
        'survey_id': surveyId,
        'question_text': q.questionText,
        'question_type': q.type.toIdentifier(),
        'is_required': q.isRequired,
        'options': q.options,
        'order_index': q.orderIndex,
        'section_title': q.sectionTitle,
        'points': q.points,
        'condition_question_id': q.conditionQuestionId,
        'condition_operator': q.conditionOperator,
        'condition_value': q.conditionValue,
      };
      
      // If the ID is a valid UUID (not a temp one maybe), include it for upsert
      if (q.id.length == 36) {
        map['id'] = q.id;
      }
      return map;
    }).toList();

    // 2. Perform UPSERT (This is much safer than delete and re-insert)
    final response = await _supabase
        .from('survey_questions')
        .upsert(data)
        .select();

    print('saveQuestions UPSERT RESPONSE: $response');
    final remainingIds = List<String>.from(response.map((x) => x['id']));
    if (remainingIds.isEmpty) {
      await _supabase
          .from('survey_questions')
          .delete()
          .eq('survey_id', surveyId);
    } else {
      await _supabase
          .from('survey_questions')
          .delete()
          .eq('survey_id', surveyId)
          .not('id', 'in', remainingIds);
    }

    return List<SurveyQuestion>.from(response.map((x) => SurveyQuestion.fromJson(x)));
  }

  static Future<String> submitResponse({
    required String surveyId,
    String? userId,
    required Map<String, dynamic> answers,
  }) async {
    final responseId = await _supabase.rpc('submit_survey_response_public', params: {
      'p_survey_id': surveyId,
      'p_user_id': userId,
      'p_answers': answers,
    });
    return responseId.toString();
  }

  static Future<void> saveResponseScore({
    required String responseId,
    required String surveyId,
    required int totalScore,
    required int maxScore,
    required int answeredCount,
  }) async {
    await _supabase.from('survey_response_scores').insert({
      'response_id': responseId,
      'survey_id': surveyId,
      'total_score': totalScore,
      'max_score': maxScore,
      'answered_count': answeredCount,
    });
  }

  static Future<Map<String, dynamic>> fetchResults(String surveyId) async {
    // This is a complex query to aggregate results
    // For now, let's just fetch all answers and aggregate in Dart
    final responses = await _supabase
        .from('survey_responses')
        .select('*, survey_answers(*)')
        .eq('survey_id', surveyId);
    
    return {
      'total_responses': responses.length,
      'responses': responses,
    };
  }
}
