import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/survey/survey.dart';
import '../../core/services/survey/survey_service.dart';

class SurveyAnalyzeView extends StatefulWidget {
  final Survey survey;
  const SurveyAnalyzeView({super.key, required this.survey});

  @override
  State<SurveyAnalyzeView> createState() => _SurveyAnalyzeViewState();
}

class _SurveyAnalyzeViewState extends State<SurveyAnalyzeView> {
  bool _isLoading = true;
  List<SurveyQuestion> _questions = [];
  Map<String, dynamic> _stats = {};

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
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalResponses = _stats['total_responses'] as int? ?? 0;

    return _isLoading 
      ? const Center(child: CircularProgressIndicator())
      : SingleChildScrollView(
          child: Column(
            children: [
              _buildAnalyzeHeader(isDark),
              Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSummaryCards(totalResponses, isDark),
                    const SizedBox(height: 40),
                    const Text('Resultater per spørsmål', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    ..._questions.map((q) => _buildResultCard(q, isDark)).toList(),
                  ],
                ),
              ),
            ],
          ),
        );
  }

  Widget _buildSummaryCards(int total, bool isDark) {
    return Row(
      children: [
        _buildStatCard('Svar totalt', '$total', Icons.people_outline, Colors.blue, isDark),
        const SizedBox(width: 20),
        _buildStatCard('Fullføringsgrad', '100%', Icons.check_circle_outline, Colors.green, isDark),
        const SizedBox(width: 20),
        _buildStatCard('Snittid', '2m 15s', Icons.timer_outlined, Colors.orange, isDark),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? DriftProTheme.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? Colors.white10 : Colors.grey[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyzeHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          const Text('Analyse', style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Eksporter data'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? Colors.white10 : Colors.grey[100],
              foregroundColor: isDark ? Colors.white : Colors.black87,
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(SurveyQuestion question, bool isDark) {
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
      margin: const EdgeInsets.only(bottom: 30),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey[200]!),
      ),
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
            child: _buildResultBody(question, rawAnswers, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildResultBody(SurveyQuestion question, List<dynamic> rawAnswers, bool isDark) {
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
            decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50], borderRadius: BorderRadius.circular(8)),
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
                  backgroundColor: isDark ? Colors.white10 : Colors.grey[200],
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
