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
  }) async {
    final Map<String, dynamic> data = {};
    if (title != null) data['title'] = title;
    if (description != null) data['description'] = description;
    if (allowAnonymous != null) data['allow_anonymous'] = allowAnonymous;
    
    if (data.isNotEmpty) {
      await _supabase.from('surveys').update(data).eq('id', id);
    }
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

    // 3. Delete any questions that are no longer in the list
    final remainingIds = List<String>.from(response.map((x) => x['id']));
    await _supabase
        .from('survey_questions')
        .delete()
        .eq('survey_id', surveyId)
        .not('id', 'in', remainingIds);

    return List<SurveyQuestion>.from(response.map((x) => SurveyQuestion.fromJson(x)));
  }

  static Future<void> submitResponse({
    required String surveyId,
    String? userId,
    required Map<String, dynamic> answers,
  }) async {
    final response = await _supabase
        .from('survey_responses')
        .insert({
          'survey_id': surveyId,
          'user_id': userId,
        })
        .select()
        .single();
    
    final responseId = response['id'];
    
    final answerData = answers.entries.map((e) => {
      'response_id': responseId,
      'question_id': e.key,
      'answer_value': e.value,
    }).toList();
    
    await _supabase.from('survey_answers').insert(answerData);
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
