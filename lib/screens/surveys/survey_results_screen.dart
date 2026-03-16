import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/survey/survey_service.dart';
import '../../models/survey/survey.dart';

class SurveyResultsScreen extends StatefulWidget {
  final Survey survey;
  const SurveyResultsScreen({super.key, required this.survey});

  @override
  State<SurveyResultsScreen> createState() => _SurveyResultsScreenState();
}

class _SurveyResultsScreenState extends State<SurveyResultsScreen> {
  bool _isLoading = true;
  int _totalResponses = 0;
  List<dynamic> _responses = [];
  List<SurveyQuestion> _questions = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final questions = await SurveyService.fetchQuestions(widget.survey.id);
      final results = await SurveyService.fetchResults(widget.survey.id);
      setState(() {
        _questions = questions;
        _totalResponses = results['total_responses'];
        _responses = results['responses'];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultater'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryCard(isDark),
                  const SizedBox(height: 24),
                  const Text('Spørsmålssammendrag', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  ..._questions.map((q) => _buildQuestionResult(q, isDark)),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [DriftProTheme.primaryGreen, DriftProTheme.primaryGreen.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: DriftProTheme.primaryGreen.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.people_outline, color: Colors.white, size: 40),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Totalt antall svar', style: TextStyle(color: Colors.white70, fontSize: 14)),
              Text('$_totalResponses', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionResult(SurveyQuestion question, bool isDark) {
    // Basic aggregation
    Map<String, int> counts = {};
    for (var resp in _responses) {
      final answers = resp['survey_answers'] as List;
      final answer = answers.firstWhere((a) => a['question_id'] == question.id, orElse: () => null);
      if (answer != null) {
        final val = answer['answer_value'].toString();
        counts[val] = (counts[val] ?? 0) + 1;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question.questionText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          if (counts.isEmpty)
            const Text('Ingen svar ennå', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
          else
            ...counts.entries.map((e) {
              final percent = _totalResponses > 0 ? e.value / _totalResponses : 0.0;
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(e.key, style: const TextStyle(fontSize: 14))),
                      Text('${(percent * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percent,
                      backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                      valueColor: const AlwaysStoppedAnimation(DriftProTheme.primaryGreen),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              );
            }).toList(),
        ],
      ),
    );
  }
}
