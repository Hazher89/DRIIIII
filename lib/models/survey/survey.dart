enum SurveyQuestionType {
  text,
  paragraph,
  single_choice,
  multiple_choice,
  dropdown,
  rating,
  date,
}

extension SurveyQuestionTypeExtension on SurveyQuestionType {
  String toIdentifier() {
    switch (this) {
      case SurveyQuestionType.text: return 'text';
      case SurveyQuestionType.paragraph: return 'paragraph';
      case SurveyQuestionType.single_choice: return 'single_choice';
      case SurveyQuestionType.multiple_choice: return 'multiple_choice';
      case SurveyQuestionType.dropdown: return 'dropdown';
      case SurveyQuestionType.rating: return 'rating';
      case SurveyQuestionType.date: return 'date';
    }
  }

  static SurveyQuestionType fromString(String val) {
    return SurveyQuestionType.values.firstWhere(
      (e) => e.toIdentifier() == val, 
      orElse: () => SurveyQuestionType.text
    );
  }
}

class Survey {
  final String id;
  final String companyId;
  final String title;
  final String? description;
  final String createdBy;
  final bool isActive;
  final bool allowAnonymous;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final int totalResponses;

  Survey({
    required this.id,
    required this.companyId,
    required this.title,
    this.description,
    required this.createdBy,
    required this.isActive,
    required this.allowAnonymous,
    this.expiresAt,
    required this.createdAt,
    this.totalResponses = 0,
  });

  factory Survey.fromJson(Map<String, dynamic> json) {
    return Survey(
      id: json['id'],
      companyId: json['company_id'],
      title: json['title'],
      description: json['description'],
      createdBy: json['created_by'],
      isActive: json['is_active'] ?? true,
      allowAnonymous: json['allow_anonymous'] ?? true,
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at']) : null,
      createdAt: DateTime.parse(json['created_at']),
      totalResponses: json['survey_responses'] != null ? (json['survey_responses'] as List).length : 0,
    );
  }
}

class SurveyQuestion {
  final String id;
  final String surveyId;
  final String questionText;
  final SurveyQuestionType type;
  final bool isRequired;
  final List<String> options;
  final int orderIndex;

  SurveyQuestion({
    required this.id,
    required this.surveyId,
    required this.questionText,
    required this.type,
    required this.isRequired,
    required this.options,
    required this.orderIndex,
  });

  factory SurveyQuestion.fromJson(Map<String, dynamic> json) {
    return SurveyQuestion(
      id: json['id'],
      surveyId: json['survey_id'],
      questionText: json['question_text'],
      type: SurveyQuestionTypeExtension.fromString(json['question_type']),
      isRequired: json['is_required'] ?? false,
      options: List<String>.from(json['options'] ?? []),
      orderIndex: json['order_index'] ?? 0,
    );
  }
}

class SurveyResponse {
  final String id;
  final String surveyId;
  final String? userId;
  final DateTime submittedAt;
  final Map<String, dynamic> metadata;

  SurveyResponse({
    required this.id,
    required this.surveyId,
    this.userId,
    required this.submittedAt,
    required this.metadata,
  });

  factory SurveyResponse.fromJson(Map<String, dynamic> json) {
    return SurveyResponse(
      id: json['id'],
      surveyId: json['survey_id'],
      userId: json['user_id'],
      submittedAt: DateTime.parse(json['submitted_at']),
      metadata: json['metadata'] ?? {},
    );
  }
}

class SurveyAnswer {
  final String id;
  final String responseId;
  final String questionId;
  final dynamic value;

  SurveyAnswer({
    required this.id,
    required this.responseId,
    required this.questionId,
    required this.value,
  });

  factory SurveyAnswer.fromJson(Map<String, dynamic> json) {
    return SurveyAnswer(
      id: json['id'],
      responseId: json['response_id'],
      questionId: json['question_id'],
      value: json['answer_value'],
    );
  }
}
