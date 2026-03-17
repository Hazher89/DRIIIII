import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
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
  bool _isSaving = false;
  List<SurveyQuestion> _questions = [];
  
  // Controllers and FocusNodes
  final Map<String, TextEditingController> _questionControllers = {};
  final Map<String, FocusNode> _questionFocusNodes = {};
  final Map<String, List<TextEditingController>> _optionControllers = {};

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    for (var c in _questionControllers.values) c.dispose();
    for (var f in _questionFocusNodes.values) f.dispose();
    for (var list in _optionControllers.values) {
      for (var c in list) c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    setState(() => _isLoading = true);
    try {
      final questions = await SurveyService.fetchQuestions(widget.survey.id);
      
      // Initialize controllers
      for (var q in questions) {
        _questionControllers[q.id] = TextEditingController(text: q.questionText);
        _questionFocusNodes[q.id] = FocusNode();
        _optionControllers[q.id] = q.options.map((opt) => TextEditingController(text: opt)).toList();
      }

      setState(() {
        _questions = questions;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Feil: $e')));
      }
    }
  }

  void _addQuestion() {
    final id = const Uuid().v4();
    final type = SurveyQuestionType.text;
    
    _questionControllers[id] = TextEditingController(text: 'Nytt spørsmål');
    _questionFocusNodes[id] = FocusNode();
    _optionControllers[id] = [];

    setState(() {
      _questions.add(SurveyQuestion(
        id: id,
        surveyId: widget.survey.id,
        questionText: 'Nytt spørsmål',
        type: type,
        isRequired: false,
        options: [],
        orderIndex: _questions.length,
      ));
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _questionFocusNodes[id]?.requestFocus();
    });
  }

  void _addOption(String qId) {
    final controller = TextEditingController(text: 'Svaralternativ');
    setState(() {
      _optionControllers[qId]?.add(controller);
    });
  }

  void _removeOption(String qId, int index) {
    setState(() {
      _optionControllers[qId]?[index].dispose();
      _optionControllers[qId]?.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    
    try {
      // Collect all data from controllers
      final List<SurveyQuestion> updatedQuestions = [];
      for (int i = 0; i < _questions.length; i++) {
        final q = _questions[i];
        final text = _questionControllers[q.id]?.text ?? q.questionText;
        final opts = _optionControllers[q.id]?.map((c) => c.text).toList() ?? q.options;
        
        updatedQuestions.add(SurveyQuestion(
          id: q.id,
          surveyId: q.surveyId,
          questionText: text,
          type: q.type,
          isRequired: q.isRequired,
          options: opts,
          orderIndex: i,
        ));
      }

      await SurveyService.saveQuestions(widget.survey.id, updatedQuestions);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alle endringer er lagret!')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunne ikke lagre: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.survey.title),
        actions: [
          if (_isSaving)
            const Center(child: Padding(padding: EdgeInsets.only(right: 16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
          else
            TextButton(
              onPressed: _save,
              child: const Text('Lagre', style: TextStyle(color: DriftProTheme.primaryGreen, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _questions.isEmpty
              ? _buildEmptyState()
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
                      _buildQuestionCard(i, isDark),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addQuestion,
        backgroundColor: DriftProTheme.primaryGreen,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_task, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text('Ingen spørsmål ennå. Trykk på + for å starte!'),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(int index, bool isDark) {
    final q = _questions[index];
    final controller = _questionControllers[q.id];
    final focusNode = _questionFocusNodes[q.id];

    return Card(
      key: ValueKey(q.id),
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
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(hintText: 'Hva vil du spørre om?', border: InputBorder.none),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  onPressed: () => setState(() => _questions.removeAt(index)),
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<SurveyQuestionType>(
                    value: q.type,
                    isExpanded: true,
                    items: SurveyQuestionType.values.map((t) {
                      return DropdownMenuItem(value: t, child: Text(t.toIdentifier().toUpperCase()));
                    }).toList(),
                    onChanged: (t) {
                      if (t != null) {
                        setState(() {
                          _questions[index] = SurveyQuestion(
                            id: q.id,
                            surveyId: q.surveyId,
                            questionText: q.questionText,
                            type: t,
                            isRequired: q.isRequired,
                            options: q.options,
                            orderIndex: index,
                          );
                          // Initialize options if switching to a choice type
                          if ([SurveyQuestionType.single_choice, SurveyQuestionType.multiple_choice, SurveyQuestionType.dropdown].contains(t)) {
                            if (_optionControllers[q.id] == null || _optionControllers[q.id]!.isEmpty) {
                              _optionControllers[q.id] = [
                                TextEditingController(text: 'Alternativ 1'),
                                TextEditingController(text: 'Alternativ 2'),
                              ];
                            }
                          }
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Row(
                  children: [
                    const Text('Påkrevd', style: TextStyle(fontSize: 12)),
                    Switch(
                      value: q.isRequired,
                      activeColor: DriftProTheme.primaryGreen,
                      onChanged: (v) {
                        setState(() {
                          _questions[index] = SurveyQuestion(
                            id: q.id,
                            surveyId: q.surveyId,
                            questionText: q.questionText,
                            type: q.type,
                            isRequired: v,
                            options: q.options,
                            orderIndex: index,
                          );
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
            if ([SurveyQuestionType.single_choice, SurveyQuestionType.multiple_choice, SurveyQuestionType.dropdown].contains(q.type))
              _buildOptionsEditor(q.id, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsEditor(String qId, bool isDark) {
    final controllers = _optionControllers[qId] ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text('SVARALTERNATIVER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.grey)),
        ...controllers.asMap().entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(Icons.circle_outlined, size: 12, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: entry.value,
                    decoration: InputDecoration(hintText: 'Skriv alternativ...', isDense: true, border: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey[300]!))),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.grey),
                  onPressed: () => _removeOption(qId, entry.key),
                ),
              ],
            ),
          );
        }),
        TextButton.icon(
          onPressed: () => _addOption(qId),
          icon: const Icon(Icons.add_circle_outline, size: 16, color: DriftProTheme.primaryGreen),
          label: const Text('Legg til alternativ', style: TextStyle(fontSize: 12, color: DriftProTheme.primaryGreen)),
        ),
      ],
    );
  }
}
