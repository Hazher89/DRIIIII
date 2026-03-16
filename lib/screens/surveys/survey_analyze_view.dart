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

    return _isLoading 
      ? const Center(child: CircularProgressIndicator())
      : SingleChildScrollView(
          child: Column(
            children: [
              _buildAnalyzeHeader(isDark),
              Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: _questions.map((q) => _buildResultCard(q, isDark)).toList(),
                ),
              ),
            ],
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
          _buildToolButton('Regler', Icons.filter_list),
          _buildToolButton('Visninger', Icons.remove_red_eye_outlined),
          _buildToolButton('Delte data', Icons.share_outlined),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.download_outlined, size: 18, color: Colors.blue),
            label: const Text('Eksporter', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              elevation: 0,
              side: BorderSide(color: Colors.grey[300]!),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: DriftProTheme.primaryGreen,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Del', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(right: 24),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildResultCard(SurveyQuestion question, bool isDark) {
    // Basic aggregation
    final responses = _stats['responses'] as List? ?? [];
    Map<String, int> counts = {};
    int totalAnswers = 0;

    for (var resp in responses) {
      final answers = resp['survey_answers'] as List;
      final answer = answers.firstWhere((a) => a['question_id'] == question.id, orElse: () => null);
      if (answer != null) {
        final val = answer['answer_value'].toString();
        counts[val] = (counts[val] ?? 0) + 1;
        totalAnswers++;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 30),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(4),
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
                Text('Svart: $totalAnswers   Hoppet over: 0', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          const Divider(height: 1),
          // Chart Placeholder (using simplified bars)
          Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              children: question.options.map((opt) {
                final count = counts[opt] ?? 0;
                final percent = totalAnswers > 0 ? count / totalAnswers : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(opt, style: const TextStyle(fontSize: 14)),
                      ),
                      Expanded(
                        flex: 5,
                        child: Stack(
                          children: [
                            Container(height: 30, color: Colors.grey[100]),
                            FractionallySizedBox(
                              widthFactor: percent,
                              child: Container(height: 30, color: (question.options.indexOf(opt) % 2 == 0) ? Colors.green : Colors.blue[700]),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('${(percent * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      Text('$count', style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
