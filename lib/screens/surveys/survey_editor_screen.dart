import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/survey/survey_service.dart';
import '../../models/survey/survey.dart';

class SurveyEditorScreen extends StatefulWidget {
  final Survey survey;
  const SurveyEditorScreen({super.key, required this.survey});

  @override
  State<SurveyEditorScreen> createState() => _SurveyEditorScreenState();
}

class _SurveyEditorScreenState extends State<SurveyEditorScreen> {
  bool _isLoading = true;
  List<SurveyQuestion> _questions = [];

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    setState(() => _isLoading = true);
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

  void _addQuestion() {
    setState(() {
      _questions.add(SurveyQuestion(
        id: DateTime.now().millisecondsSinceEpoch.toString(), // Temporary ID
        surveyId: widget.survey.id,
        questionText: 'Nytt spørsmål',
        type: SurveyQuestionType.text,
        isRequired: false,
        options: [],
        orderIndex: _questions.length,
      ));
    });
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    try {
      await SurveyService.saveQuestions(widget.survey.id, _questions);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lagret')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved lagring: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.survey.title),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Lagre', style: TextStyle(color: DriftProTheme.primaryGreen, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ReorderableListView(
              padding: const EdgeInsets.all(16),
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _questions.removeAt(oldIndex);
                  _questions.insert(newIndex, item);
                });
              },
              children: [
                for (int i = 0; i < _questions.length; i++)
                  _buildQuestionCard(i),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addQuestion,
        backgroundColor: DriftProTheme.primaryGreen,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildQuestionCard(int index) {
    final question = _questions[index];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      key: ValueKey(question.id),
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.drag_indicator, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: question.questionText,
                    decoration: const InputDecoration(hintText: 'Spørsmålstekst', border: InputBorder.none),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    onChanged: (v) {
                      _questions[index] = SurveyQuestion(
                        id: question.id,
                        surveyId: question.surveyId,
                        questionText: v,
                        type: question.type,
                        isRequired: question.isRequired,
                        options: question.options,
                        orderIndex: index,
                      );
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red, size: 20),
                  onPressed: () => setState(() => _questions.removeAt(index)),
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<SurveyQuestionType>(
                    value: question.type,
                    isExpanded: true,
                    items: SurveyQuestionType.values.map((t) {
                      return DropdownMenuItem(value: t, child: Text(t.name.toUpperCase()));
                    }).toList(),
                    onChanged: (t) {
                      if (t != null) {
                        setState(() {
                          _questions[index] = SurveyQuestion(
                            id: question.id,
                            surveyId: question.surveyId,
                            questionText: question.questionText,
                            type: t,
                            isRequired: question.isRequired,
                            options: question.options,
                            orderIndex: index,
                          );
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Row(
                  children: [
                    const Text('Påkrevd'),
                    Switch(
                      value: question.isRequired,
                      activeColor: DriftProTheme.primaryGreen,
                      onChanged: (v) {
                        setState(() {
                          _questions[index] = SurveyQuestion(
                            id: question.id,
                            surveyId: question.surveyId,
                            questionText: question.questionText,
                            type: question.type,
                            isRequired: v,
                            options: question.options,
                            orderIndex: index,
                          );
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
            if ([SurveyQuestionType.multiple_choice, SurveyQuestionType.checkbox, SurveyQuestionType.dropdown].contains(question.type))
              _buildOptionsEditor(index),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsEditor(int index) {
    final question = _questions[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text('Alternativer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ...question.options.asMap().entries.map((entry) {
          return Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: entry.value,
                  decoration: InputDecoration(hintText: 'Alternativ ${entry.key + 1}', isDense: true),
                  onChanged: (v) {
                    final newOptions = List<String>.from(question.options);
                    newOptions[entry.key] = v;
                    _questions[index] = SurveyQuestion(
                      id: question.id,
                      surveyId: question.surveyId,
                      questionText: question.questionText,
                      type: question.type,
                      isRequired: question.isRequired,
                      options: newOptions,
                      orderIndex: index,
                    );
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.grey),
                onPressed: () {
                  setState(() {
                    final newOptions = List<String>.from(question.options);
                    newOptions.removeAt(entry.key);
                    _questions[index] = SurveyQuestion(
                      id: question.id,
                      surveyId: question.surveyId,
                      questionText: question.questionText,
                      type: question.type,
                      isRequired: question.isRequired,
                      options: newOptions,
                      orderIndex: index,
                    );
                  });
                },
              ),
            ],
          );
        }),
        TextButton.icon(
          onPressed: () {
            setState(() {
              final newOptions = List<String>.from(question.options);
              newOptions.add('Nytt alternativ');
              _questions[index] = SurveyQuestion(
                id: question.id,
                surveyId: question.surveyId,
                questionText: question.questionText,
                type: question.type,
                isRequired: question.isRequired,
                options: newOptions,
                orderIndex: index,
              );
            });
          },
          icon: const Icon(Icons.add_circle_outline, size: 16),
          label: const Text('Legg til alternativ'),
        ),
      ],
    );
  }
}
