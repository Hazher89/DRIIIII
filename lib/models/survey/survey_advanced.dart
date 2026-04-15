class SurveyThemeConfig {
  final String surveyId;
  final String primaryHex;
  final String backgroundHex;
  final String cardHex;
  final String textHex;
  final String accentHex;
  final String? logoUrl;
  final String fontFamily;
  final String buttonStyle;
  final bool darkModeForRespondent;
  final bool compactMode;
  final bool showProgressBar;
  final bool showEstimatedTime;
  final DateTime? updatedAt;

  const SurveyThemeConfig({
    required this.surveyId,
    this.primaryHex = '#1B5E20',
    this.backgroundHex = '#F7F9F8',
    this.cardHex = '#FFFFFF',
    this.textHex = '#0F172A',
    this.accentHex = '#0D47A1',
    this.logoUrl,
    this.fontFamily = 'Inter',
    this.buttonStyle = 'rounded',
    this.darkModeForRespondent = false,
    this.compactMode = false,
    this.showProgressBar = true,
    this.showEstimatedTime = true,
    this.updatedAt,
  });

  factory SurveyThemeConfig.fromJson(Map<String, dynamic> json) {
    return SurveyThemeConfig(
      surveyId: json['survey_id'] as String,
      primaryHex: json['primary_hex'] as String? ?? '#1B5E20',
      backgroundHex: json['background_hex'] as String? ?? '#F7F9F8',
      cardHex: json['card_hex'] as String? ?? '#FFFFFF',
      textHex: json['text_hex'] as String? ?? '#0F172A',
      accentHex: json['accent_hex'] as String? ?? '#0D47A1',
      logoUrl: json['logo_url'] as String?,
      fontFamily: json['font_family'] as String? ?? 'Inter',
      buttonStyle: json['button_style'] as String? ?? 'rounded',
      darkModeForRespondent: json['dark_mode_for_respondent'] as bool? ?? false,
      compactMode: json['compact_mode'] as bool? ?? false,
      showProgressBar: json['show_progress_bar'] as bool? ?? true,
      showEstimatedTime: json['show_estimated_time'] as bool? ?? true,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'survey_id': surveyId,
        'primary_hex': primaryHex,
        'background_hex': backgroundHex,
        'card_hex': cardHex,
        'text_hex': textHex,
        'accent_hex': accentHex,
        'logo_url': logoUrl,
        'font_family': fontFamily,
        'button_style': buttonStyle,
        'dark_mode_for_respondent': darkModeForRespondent,
        'compact_mode': compactMode,
        'show_progress_bar': showProgressBar,
        'show_estimated_time': showEstimatedTime,
      };
}

class SurveyArchiveEntry {
  final String id;
  final String surveyId;
  final String companyId;
  final String title;
  final String status;
  final String archivedBy;
  final DateTime archivedAt;
  final int responsesAtArchive;
  final String? note;

  const SurveyArchiveEntry({
    required this.id,
    required this.surveyId,
    required this.companyId,
    required this.title,
    required this.status,
    required this.archivedBy,
    required this.archivedAt,
    required this.responsesAtArchive,
    this.note,
  });

  factory SurveyArchiveEntry.fromJson(Map<String, dynamic> json) {
    return SurveyArchiveEntry(
      id: json['id'] as String,
      surveyId: json['survey_id'] as String,
      companyId: json['company_id'] as String,
      title: json['title'] as String,
      status: json['status'] as String? ?? 'archived',
      archivedBy: json['archived_by'] as String,
      archivedAt: DateTime.parse(json['archived_at'] as String),
      responsesAtArchive: (json['responses_at_archive'] as num?)?.toInt() ?? 0,
      note: json['note'] as String?,
    );
  }
}

class SurveyAnalyticsSnapshot {
  final String id;
  final String surveyId;
  final int totalResponses;
  final int completedResponses;
  final double completionRate;
  final double averageDurationSec;
  final int dropOffCount;
  final double sentimentScore;
  final Map<String, dynamic> topThemes;
  final DateTime generatedAt;

  const SurveyAnalyticsSnapshot({
    required this.id,
    required this.surveyId,
    required this.totalResponses,
    required this.completedResponses,
    required this.completionRate,
    required this.averageDurationSec,
    required this.dropOffCount,
    required this.sentimentScore,
    required this.topThemes,
    required this.generatedAt,
  });

  factory SurveyAnalyticsSnapshot.fromJson(Map<String, dynamic> json) {
    return SurveyAnalyticsSnapshot(
      id: json['id'] as String,
      surveyId: json['survey_id'] as String,
      totalResponses: (json['total_responses'] as num?)?.toInt() ?? 0,
      completedResponses: (json['completed_responses'] as num?)?.toInt() ?? 0,
      completionRate: (json['completion_rate'] as num?)?.toDouble() ?? 0,
      averageDurationSec:
          (json['average_duration_sec'] as num?)?.toDouble() ?? 0,
      dropOffCount: (json['drop_off_count'] as num?)?.toInt() ?? 0,
      sentimentScore: (json['sentiment_score'] as num?)?.toDouble() ?? 0,
      topThemes: json['top_themes'] as Map<String, dynamic>? ?? const {},
      generatedAt: DateTime.parse(json['generated_at'] as String),
    );
  }
}

