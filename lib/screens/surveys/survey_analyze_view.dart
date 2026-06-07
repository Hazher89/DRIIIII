import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/survey/survey_analytics_engine.dart';
import '../../core/services/survey/survey_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/driftpro_colors.dart';
import '../../core/theme/driftpro_theme_context.dart';
import '../../models/survey/survey.dart';

class SurveyAnalyzeView extends StatefulWidget {
  final Survey survey;
  final bool embedded;

  const SurveyAnalyzeView({super.key, required this.survey, this.embedded = false});

  @override
  State<SurveyAnalyzeView> createState() => _SurveyAnalyzeViewState();
}

class _SurveyAnalyzeViewState extends State<SurveyAnalyzeView> {
  bool _isLoading = true;
  List<SurveyQuestion> _questions = [];
  Map<String, dynamic> _stats = {};
  SurveySummaryMetrics? _metrics;

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  Future<void> _loadResults() async {
    setState(() => _isLoading = true);
    try {
      final questions = await SurveyService.fetchQuestions(widget.survey.id);
      final results = await SurveyService.fetchResults(widget.survey.id);
      setState(() {
        _questions = questions;
        _stats = results;
        _metrics = SurveyAnalyticsEngine.computeSummary(
          questions: questions,
          rawResults: results,
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportCsv() async {
    final csv = SurveyAnalyticsEngine.exportCsv(
      survey: widget.survey,
      questions: _questions,
      rawResults: _stats,
    );
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV eksportert til utklippstavle')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final m = _metrics;

    return _isLoading
      ? const Center(child: CircularProgressIndicator())
      : SingleChildScrollView(
          child: Column(
            children: [
              if (!widget.embedded) _buildAnalyzeHeader(drift),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.embedded)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          children: [
                            Text('Nøkkeltall', style: DriftProTheme.headingSm.copyWith(color: drift.textPrimary)),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _exportCsv,
                              icon: const Icon(Icons.download_outlined, size: 18),
                              label: const Text('Eksporter CSV'),
                            ),
                          ],
                        ),
                      ),
                    _buildSummaryCards(m, drift),
                    if (m?.npsScore != null) ...[
                      const SizedBox(height: 20),
                      _buildNpsPanel(m!, drift),
                    ],
                    const SizedBox(height: 32),
                    Text(
                      'Resultater per spørsmål',
                      style: DriftProTheme.headingMd.copyWith(color: drift.textPrimary),
                    ),
                    const SizedBox(height: 16),
                    ..._questions.map((q) => _buildResultCard(q, drift)),
                  ],
                ),
              ),
            ],
          ),
        );
  }

  Widget _buildSummaryCards(SurveySummaryMetrics? m, DriftProColors drift) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > 700;
        final cards = [
          _buildStatCard('Svar totalt', '${m?.totalResponses ?? 0}', Icons.people_outline, Colors.blue, drift),
          _buildStatCard(
            'Fullføringsgrad',
            m != null ? '${m.completionRate.toStringAsFixed(0)}%' : '—',
            Icons.check_circle_outline,
            Colors.green,
            drift,
          ),
          _buildStatCard(
            'Snittid',
            m?.formattedDuration ?? '—',
            Icons.timer_outlined,
            Colors.orange,
            drift,
          ),
        ];
        if (wide) {
          return Row(
            children: cards
                .map((card) => Expanded(child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: card,
                    )))
                .toList(),
          );
        }
        return Column(
          children: cards.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: c,
              )).toList(),
        );
      },
    );
  }

  Widget _buildNpsPanel(SurveySummaryMetrics m, DriftProColors drift) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: drift.surfaceDecoration(radius: 14, elevated: true),
      child: Row(
        children: [
          Text(
            m.npsScore!.toStringAsFixed(0),
            style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.purple),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Net Promoter Score', style: DriftProTheme.headingSm.copyWith(color: drift.textPrimary)),
                const SizedBox(height: 8),
                Text(
                  'Promotører: ${m.npsPromoters} · Passive: ${m.npsPassives} · Detraktorer: ${m.npsDetractors}',
                  style: DriftProTheme.bodySm.copyWith(color: drift.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, DriftProColors drift) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: drift.surfaceDecoration(radius: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: DriftProTheme.bodySm.copyWith(color: drift.textMuted)),
          ],
        ),
      );
  }

  Widget _buildAnalyzeHeader(DriftProColors drift) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: drift.card,
        border: Border(bottom: BorderSide(color: drift.borderSubtle)),
      ),
      child: Row(
        children: [
          Text('Analyse', style: DriftProTheme.headingSm.copyWith(color: drift.textPrimary)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _exportCsv,
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Eksporter CSV'),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(SurveyQuestion question, DriftProColors drift) {
    final responses = _stats['responses'] as List? ?? [];
    List<dynamic> rawAnswers = [];

    for (var resp in responses) {
      final answers = resp['survey_answers'] as List;
      final answer = answers.firstWhere((a) => a['question_id'] == question.id, orElse: () => null);
      if (answer != null) {
        rawAnswers.add(answer['answer_value']);
      }
    }

    final totalAnswers = rawAnswers.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: drift.surfaceDecoration(radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(question.questionText, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Type: ${question.type.name} • Svar: $totalAnswers', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(24),
            child: _buildResultBody(question, rawAnswers, drift),
          ),
        ],
      ),
    );
  }

  Widget _buildResultBody(SurveyQuestion question, List<dynamic> rawAnswers, DriftProColors drift) {
    if (question.type == SurveyQuestionType.matrix && rawAnswers.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rawAnswers.take(5).map((ans) {
          if (ans is Map) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(ans.entries.map((e) => '${e.key}: ${e.value}').join(' · ')),
            );
          }
          return Text(ans.toString());
        }).toList(),
      );
    }

    if (question.type == SurveyQuestionType.ranking && rawAnswers.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rawAnswers.take(5).map((ans) {
          final list = ans is List ? ans : [ans.toString()];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(list.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join(' → ')),
          );
        }).toList(),
      );
    }

    if (question.type == SurveyQuestionType.text ||
        question.type == SurveyQuestionType.paragraph ||
        question.type == SurveyQuestionType.url ||
        question.type == SurveyQuestionType.time) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Individuelle svar:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          ...rawAnswers.take(10).map((ans) => Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: drift.surfaceMuted, borderRadius: BorderRadius.circular(8)),
            child: Text(ans.toString()),
          )).toList(),
          if (rawAnswers.length > 10)
            TextButton(onPressed: () {}, child: const Text('Se alle svar')),
        ],
      );
    }

    if (question.type == SurveyQuestionType.slider) {
      final values = rawAnswers
          .map((a) => double.tryParse(a.toString()))
          .whereType<double>()
          .toList();
      if (values.isEmpty) {
        return const Text('Ingen numeriske svar ennå.');
      }
      values.sort();
      final sum = values.fold<double>(0, (a, b) => a + b);
      final avg = sum / values.length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gjennomsnitt ${avg.toStringAsFixed(2)} · min ${values.first.toStringAsFixed(2)} · maks ${values.last.toStringAsFixed(2)} · n = ${values.length}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Text('Viser opptil 20 enkeltverdier:', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          const SizedBox(height: 8),
          ...values.take(20).map((v) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(v.toStringAsFixed(4)),
              )),
          if (values.length > 20)
            Text(
              '… og ${values.length - 20} til',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
        ],
      );
    }

    // Aggregation for valg / NPS / rangering m.m.
    final Map<String, int> counts = {};
    for (var ans in rawAnswers) {
      if (ans is List) {
        for (var subAns in ans) {
          counts[subAns.toString()] = (counts[subAns.toString()] ?? 0) + 1;
        }
      } else {
        counts[ans.toString()] = (counts[ans.toString()] ?? 0) + 1;
      }
    }

    final totalCount = rawAnswers.length;

    final List<String> labels = [
      SurveyQuestionType.single_choice,
      SurveyQuestionType.multiple_choice,
      SurveyQuestionType.dropdown,
      SurveyQuestionType.likert,
    ].contains(question.type)
        ? List<String>.from(question.options)
        : (counts.keys.toList()..sort());

    if (labels.isEmpty) {
      return const Text('Ingen svar å visualisere.');
    }

    return Column(
      children: labels.map((opt) {
        final count = counts[opt] ?? 0;
        final percent = totalCount > 0 ? count / totalCount : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(opt, style: const TextStyle(fontSize: 14))),
                  Text('$count (${(percent * 100).toInt()}%)', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percent,
                  minHeight: 12,
                  backgroundColor: drift.borderSubtle,
                  valueColor: const AlwaysStoppedAnimation<Color>(DriftProTheme.primaryGreen),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
