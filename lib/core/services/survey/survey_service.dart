import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/survey/survey.dart';

class SurveyService {
  static final _supabase = Supabase.instance.client;

  static Future<List<Survey>> fetchSurveys({required String companyId}) async {
    final response = await _supabase
        .from('surveys')
        .select()
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

  static Future<void> saveQuestions(String surveyId, List<SurveyQuestion> questions) async {
    // Basic approach: delete and re-insert for simplicity in editor
    await _supabase.from('survey_questions').delete().eq('survey_id', surveyId);
    
    if (questions.isNotEmpty) {
      await _supabase.from('survey_questions').insert(
        questions.map((q) => {
          'survey_id': surveyId,
          'question_text': q.questionText,
          'question_type': q.type.name,
          'is_required': q.isRequired,
          'options': q.options,
          'order_index': q.orderIndex,
        }).toList()
      );
    }
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
