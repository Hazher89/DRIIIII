import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/survey/survey.dart';
import '../../core/services/survey/survey_service.dart';
import '../../core/services/supabase_service.dart';

class SurveyPlayerScreen extends StatefulWidget {
  final String surveyId;
  const SurveyPlayerScreen({super.key, required this.surveyId});

  @override
  State<SurveyPlayerScreen> createState() => _SurveyPlayerScreenState();
}

class _SurveyPlayerScreenState extends State<SurveyPlayerScreen> {
  bool _isLoading = true;
  bool _isSubmitting = false;
  Survey? _survey;
  List<SurveyQuestion> _questions = [];
  final Map<String, dynamic> _answers = {};
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadSurveyData();
  }

  Future<void> _loadSurveyData() async {
    setState(() => _isLoading = true);
    try {
      // In a real public scenario, we might need a public fetch method
      // For now, assuming authenticated or using the standard service
      final surveys = await SurveyService.fetchSurveys(companyId: ''); // Need a way to fetch by ID
      // Refined: Fetch specific survey
      final survey = await _fetchSurveyById(widget.surveyId);
      final questions = await SurveyService.fetchQuestions(widget.surveyId);
      
      setState(() {
        _survey = survey;
        _questions = questions;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke laste undersøkelsen: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<Survey> _fetchSurveyById(String id) async {
    final response = await SupabaseService.client
        .from('surveys')
        .select()
        .eq('id', id)
        .single();
    return Survey.fromJson(response);
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSubmitting = true);
      try {
        final userId = SupabaseService.currentUser?.id;
        await SurveyService.submitResponse(
          surveyId: widget.surveyId,
          userId: userId,
          answers: _answers,
        );
        
        if (mounted) {
          _showSuccessDialog();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Kunne ikke sende svar: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Takk!'),
        content: const Text('Dine svar har blitt registrert.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back
            },
            child: const Text('Lukk'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_survey == null) {
      return const Scaffold(body: Center(child: Text('Undersøkelsen ble ikke funnet.')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_survey!.title),
        elevation: 0,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_survey!.description != null && _survey!.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: Text(
                      _survey!.description!,
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ),
                ..._questions.map((q) => _buildQuestionWidget(q)),
                const SizedBox(height: 48),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DriftProTheme.primaryGreen,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('SEND INN SVAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionWidget(SurveyQuestion q) {
    return Container(
      margin: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  q.questionText,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              if (q.isRequired)
                const Text(' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          _buildAnswerInput(q),
        ],
      ),
    );
  }

  Widget _buildAnswerInput(SurveyQuestion q) {
    switch (q.type) {
      case SurveyQuestionType.single_choice:
        return Column(
          children: q.options.map((opt) => RadioListTile<String>(
            title: Text(opt),
            value: opt,
            groupValue: _answers[q.id],
            activeColor: DriftProTheme.primaryGreen,
            onChanged: (val) => setState(() => _answers[q.id] = val),
            contentPadding: EdgeInsets.zero,
          )).toList(),
        );
      case SurveyQuestionType.multiple_choice:
        _answers[q.id] ??= <String>[];
        return Column(
          children: q.options.map((opt) => CheckboxListTile(
            title: Text(opt),
            value: (_answers[q.id] as List).contains(opt),
            activeColor: DriftProTheme.primaryGreen,
            onChanged: (val) {
              setState(() {
                if (val == true) {
                  (_answers[q.id] as List).add(opt);
                } else {
                  (_answers[q.id] as List).remove(opt);
                }
              });
            },
            contentPadding: EdgeInsets.zero,
          )).toList(),
        );
      case SurveyQuestionType.text:
        return TextFormField(
          decoration: InputDecoration(
            hintText: 'Ditt svar...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (val) => _answers[q.id] = val,
          validator: q.isRequired ? (v) => v == null || v.isEmpty ? 'Vennligst svar på dette' : null : null,
        );
      case SurveyQuestionType.paragraph:
        return TextFormField(
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Ditt svar...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (val) => _answers[q.id] = val,
          validator: q.isRequired ? (v) => v == null || v.isEmpty ? 'Vennligst svar på dette' : null : null,
        );
      case SurveyQuestionType.rating:
        return Row(
          children: List.generate(5, (index) {
            final rating = index + 1;
            return IconButton(
              icon: Icon(
                rating <= (_answers[q.id] ?? 0) ? Icons.star : Icons.star_outline,
                color: DriftProTheme.primaryGreen,
                size: 40,
              ),
              onPressed: () => setState(() => _answers[q.id] = rating),
            );
          }),
        );
      default:
        return const SizedBox();
    }
  }
}
