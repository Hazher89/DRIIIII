enum SurveyQuestionType {
  text,
  paragraph,
  single_choice,
  multiple_choice,
  dropdown,
  rating,
  date,
  yes_no,
  number,
  email,
  phone,
  nps,
  likert,
  slider,
  time,
  url,
  matrix,
  ranking,
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
      case SurveyQuestionType.yes_no: return 'yes_no';
      case SurveyQuestionType.number: return 'number';
      case SurveyQuestionType.email: return 'email';
      case SurveyQuestionType.phone: return 'phone';
      case SurveyQuestionType.nps: return 'nps';
      case SurveyQuestionType.likert: return 'likert';
      case SurveyQuestionType.slider: return 'slider';
      case SurveyQuestionType.time: return 'time';
      case SurveyQuestionType.url: return 'url';
      case SurveyQuestionType.matrix: return 'matrix';
      case SurveyQuestionType.ranking: return 'ranking';
    }
  }

  static SurveyQuestionType fromString(String val) {
    return SurveyQuestionType.values.firstWhere(
      (e) => e.toIdentifier() == val,
      orElse: () {
        // Nyere typer i DB som appen ikke kjenner — fall tilbake til tekst.
        return SurveyQuestionType.text;
      },
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
  final String theme;
  final DateTime? expiresAt;
  final String? adminNotes;
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
    this.theme = 'Original',
    this.expiresAt,
    this.adminNotes,
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
      theme: json['theme'] ?? 'Original',
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at']) : null,
      adminNotes: json['admin_notes'] as String?,
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
  final String? sectionTitle;
  final int points;
  final String? conditionQuestionId;
  final String? conditionOperator;
  final String? conditionValue;

  SurveyQuestion({
    required this.id,
    required this.surveyId,
    required this.questionText,
    required this.type,
    required this.isRequired,
    required this.options,
    required this.orderIndex,
    this.sectionTitle,
    this.points = 0,
    this.conditionQuestionId,
    this.conditionOperator,
    this.conditionValue,
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
      sectionTitle: json['section_title'],
      points: json['points'] ?? 0,
      conditionQuestionId: json['condition_question_id'],
      conditionOperator: json['condition_operator'],
      conditionValue: json['condition_value'],
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
