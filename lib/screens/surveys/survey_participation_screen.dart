import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/survey/survey_service.dart';
import '../../models/survey/survey.dart';
import '../../core/services/supabase_service.dart';

class SurveyParticipationScreen extends StatefulWidget {
  final Survey survey;
  const SurveyParticipationScreen({super.key, required this.survey});

  @override
  State<SurveyParticipationScreen> createState() => _SurveyParticipationScreenState();
}

class _SurveyParticipationScreenState extends State<SurveyParticipationScreen> {
  bool _isLoading = true;
  List<SurveyQuestion> _questions = [];
  final Map<String, dynamic> _answers = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    try {
      final questions = await SurveyService.fetchQuestions(widget.survey.id);
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    // Validation
    for (var q in _questions) {
      if (q.isRequired && (_answers[q.id] == null || _answers[q.id].toString().isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Vennligst svar på påkrevd spørsmål: ${q.questionText}')),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      final user = SupabaseService.currentUser;
      await SurveyService.submitResponse(
        surveyId: widget.survey.id,
        userId: user?.id,
        answers: _answers,
      );
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Takk!'),
            content: const Text('Ditt svar har blitt registrert.'),
            actions: [
              TextButton(onPressed: () => Navigator.popUntil(context, (r) => r.isFirst), child: const Text('Ferdig')),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved innsending: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: Text(widget.survey.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.survey.description != null) ...[
              Text(widget.survey.description!, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 24),
            ],
            ..._questions.map((q) => _buildQuestionWidget(q)),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DriftProTheme.primaryGreen,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Send inn svar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionWidget(SurveyQuestion q) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  q.questionText,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              if (q.isRequired) const Text(' *', style: TextStyle(color: Colors.red)),
            ],
          ),
          const SizedBox(height: 12),
          _buildAnswerInput(q),
        ],
      ),
    );
  }

  Widget _buildAnswerInput(SurveyQuestion q) {
    switch (q.type) {
      case SurveyQuestionType.text:
      case SurveyQuestionType.paragraph:
        return TextField(
          maxLines: q.type == SurveyQuestionType.paragraph ? 4 : 1,
          decoration: InputDecoration(
            hintText: 'Svaret ditt',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (v) => _answers[q.id] = v,
        );
      case SurveyQuestionType.multiple_choice:
      case SurveyQuestionType.dropdown:
        return Column(
          children: q.options.map((opt) {
            return RadioListTile<String>(
              title: Text(opt),
              value: opt,
              groupValue: _answers[q.id],
              onChanged: (v) => setState(() => _answers[q.id] = v),
              activeColor: DriftProTheme.primaryGreen,
            );
          }).toList(),
        );
      case SurveyQuestionType.checkbox:
        return Column(
          children: q.options.map((opt) {
            final list = (_answers[q.id] as List<String>?) ?? [];
            return CheckboxListTile(
              title: Text(opt),
              value: list.contains(opt),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    list.add(opt);
                  } else {
                    list.remove(opt);
                  }
                  _answers[q.id] = list;
                });
              },
              activeColor: DriftProTheme.primaryGreen,
            );
          }).toList(),
        );
      default:
        return const Text('Ikke støttet ennå');
    }
  }
}
