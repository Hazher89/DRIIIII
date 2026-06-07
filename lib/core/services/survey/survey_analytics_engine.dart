import '../../../models/survey/survey.dart';

class SurveySummaryMetrics {
  const SurveySummaryMetrics({
    required this.totalResponses,
    required this.completedResponses,
    required this.completionRate,
    required this.averageDurationSec,
    this.npsScore,
    this.npsPromoters = 0,
    this.npsPassives = 0,
    this.npsDetractors = 0,
  });

  final int totalResponses;
  final int completedResponses;
  final double completionRate;
  final double averageDurationSec;
  final double? npsScore;
  final int npsPromoters;
  final int npsPassives;
  final int npsDetractors;

  String get formattedDuration {
    if (averageDurationSec <= 0) return '—';
    final m = (averageDurationSec / 60).floor();
    final s = (averageDurationSec % 60).round();
    if (m <= 0) return '${s}s';
    return '${m}m ${s}s';
  }
}

class SurveyAnalyticsEngine {
  SurveyAnalyticsEngine._();

  static List<Map<String, dynamic>> _answersForQuestion(
    List<dynamic> responses,
    String questionId,
  ) {
    final out = <dynamic>[];
    for (final resp in responses) {
      final answers = resp['survey_answers'] as List? ?? [];
      for (final a in answers) {
        if (a['question_id'] == questionId) {
          out.add(a['answer_value']);
        }
      }
    }
    return out.map((e) => {'value': e}).toList();
  }

  static SurveySummaryMetrics computeSummary({
    required List<SurveyQuestion> questions,
    required Map<String, dynamic> rawResults,
  }) {
    final responses = rawResults['responses'] as List? ?? [];
    final total = responses.length;
    if (total == 0) {
      return const SurveySummaryMetrics(
        totalResponses: 0,
        completedResponses: 0,
        completionRate: 0,
        averageDurationSec: 0,
      );
    }

    final requiredIds =
        questions.where((q) => q.isRequired).map((q) => q.id).toSet();

    var completed = 0;
    var durationSum = 0.0;
    var durationCount = 0;

    for (final resp in responses) {
      final answers = resp['survey_answers'] as List? ?? [];
      final answeredIds =
          answers.map((a) => a['question_id'] as String).toSet();
      if (requiredIds.isEmpty || requiredIds.every(answeredIds.contains)) {
        completed++;
      }
      final meta = resp['metadata'];
      if (meta is Map && meta['duration_sec'] != null) {
        final d = (meta['duration_sec'] as num?)?.toDouble();
        if (d != null && d > 0) {
          durationSum += d;
          durationCount++;
        }
      }
    }

    double? nps;
    int promoters = 0, passives = 0, detractors = 0;
    final npsQuestions = questions.where((q) => q.type == SurveyQuestionType.nps);
    if (npsQuestions.isNotEmpty) {
      final npsId = npsQuestions.first.id;
      final scores = <int>[];
      for (final resp in responses) {
        final answers = resp['survey_answers'] as List? ?? [];
        for (final a in answers) {
          if (a['question_id'] == npsId) {
            final v = int.tryParse(a['answer_value'].toString());
            if (v != null && v >= 0 && v <= 10) scores.add(v);
          }
        }
      }
      if (scores.isNotEmpty) {
        for (final s in scores) {
          if (s >= 9) {
            promoters++;
          } else if (s >= 7) {
            passives++;
          } else {
            detractors++;
          }
        }
        nps = ((promoters - detractors) / scores.length) * 100;
      }
    }

    return SurveySummaryMetrics(
      totalResponses: total,
      completedResponses: completed,
      completionRate: total > 0 ? (completed / total) * 100 : 0,
      averageDurationSec: durationCount > 0 ? durationSum / durationCount : 0,
      npsScore: nps,
      npsPromoters: promoters,
      npsPassives: passives,
      npsDetractors: detractors,
    );
  }

  static Map<String, int> choiceCounts(SurveyQuestion q, List<dynamic> responses) {
    final counts = <String, int>{};
    for (final resp in responses) {
      final answers = resp['survey_answers'] as List? ?? [];
      for (final a in answers) {
        if (a['question_id'] != q.id) continue;
        final val = a['answer_value'];
        if (val is List) {
          for (final item in val) {
            final k = item.toString();
            counts[k] = (counts[k] ?? 0) + 1;
          }
        } else {
          final k = val.toString();
          counts[k] = (counts[k] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  static String exportCsv({
    required Survey survey,
    required List<SurveyQuestion> questions,
    required Map<String, dynamic> rawResults,
  }) {
    final responses = rawResults['responses'] as List? ?? [];
    final buffer = StringBuffer();

    buffer.write('response_id,submitted_at,user_id');
    for (final q in questions) {
      buffer.write(',"${_escapeCsv(q.questionText)}"');
    }
    buffer.writeln();

    for (final resp in responses) {
      buffer.write('${resp['id']},${resp['submitted_at']},${resp['user_id'] ?? ''}');
      final answers = resp['survey_answers'] as List? ?? [];
      final byQ = <String, dynamic>{};
      for (final a in answers) {
        byQ[a['question_id'] as String] = a['answer_value'];
      }
      for (final q in questions) {
        buffer.write(',"${_escapeCsv(_formatAnswer(byQ[q.id]))}"');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  static String _formatAnswer(dynamic v) {
    if (v == null) return '';
    if (v is Map) return v.entries.map((e) => '${e.key}: ${e.value}').join('; ');
    if (v is List) return v.join(' > ');
    return v.toString();
  }

  static String _escapeCsv(String s) =>
      s.replaceAll('"', '""').replaceAll('\n', ' ');
}
