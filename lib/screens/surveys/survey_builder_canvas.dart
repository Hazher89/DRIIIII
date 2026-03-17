import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../models/survey/survey.dart';
import '../../core/services/survey/survey_service.dart';

class SurveyBuilderCanvas extends StatefulWidget {
  final Survey survey;
  const SurveyBuilderCanvas({super.key, required this.survey});

  @override
  State<SurveyBuilderCanvas> createState() => _SurveyBuilderCanvasState();
}

class _SurveyBuilderCanvasState extends State<SurveyBuilderCanvas> {
  bool _isLoading = true;
  bool _isSaving = false;
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
        id: const Uuid().v4(),
        surveyId: widget.survey.id,
        questionText: 'Nytt spørsmål',
        type: SurveyQuestionType.single_choice,
        isRequired: false,
        options: ['Alternativ 1'],
        orderIndex: _questions.length,
      ));
    });
  }

  void _removeQuestion(int index) {
    setState(() {
      _questions.removeAt(index);
      // Update order indices
      for (int i = 0; i < _questions.length; i++) {
        final q = _questions[i];
        _questions[i] = SurveyQuestion(
          id: q.id,
          surveyId: q.surveyId,
          questionText: q.questionText,
          type: q.type,
          isRequired: q.isRequired,
          options: q.options,
          orderIndex: i,
        );
      }
    });
  }

  void _updateQuestion(int index, SurveyQuestion newQ) {
    setState(() {
      _questions[index] = newQ;
    });
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      await SurveyService.saveQuestions(widget.survey.id, _questions);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Undersøkelsen er lagret!'), backgroundColor: DriftProTheme.primaryGreen),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke lagre: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        _buildStyleSidebar(isDark),
        Expanded(
          child: Container(
            color: isDark ? DriftProTheme.surfaceDark : const Color(0xFFF5F7F8),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                margin: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: isDark ? DriftProTheme.cardDark : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))
                  ],
                ),
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator())
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildCanvasHeader(),
                            _buildQuestionsList(),
                            const SizedBox(height: 40),
                            _buildCanvasFooter(),
                          ],
                        ),
                      ),
                    ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStyleSidebar(bool isDark) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        border: Border(right: BorderSide(color: isDark ? Colors.white10 : Colors.grey[200]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Spørsmål-typer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                _buildQuestionTypeItem(Icons.radio_button_checked, 'Enkeltvalg', SurveyQuestionType.single_choice),
                _buildQuestionTypeItem(Icons.check_box_outlined, 'Flervalg', SurveyQuestionType.multiple_choice),
                _buildQuestionTypeItem(Icons.short_text, 'Kort tekst', SurveyQuestionType.text),
                _buildQuestionTypeItem(Icons.notes, 'Lang tekst', SurveyQuestionType.paragraph),
                _buildQuestionTypeItem(Icons.star_outline, 'Rangering', SurveyQuestionType.rating),
                _buildQuestionTypeItem(Icons.calendar_today_outlined, 'Dato', SurveyQuestionType.date),
                _buildQuestionTypeItem(Icons.arrow_drop_down_circle_outlined, 'Nedtrekk', SurveyQuestionType.dropdown),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('INNSTILLINGER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 12),
                _buildSidebarToggle('Anonyme svar', widget.survey.allowAnonymous),
                _buildSidebarToggle('Krev pålogging', !widget.survey.allowAnonymous),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionTypeItem(IconData icon, String label, SurveyQuestionType type) {
    return ListTile(
      leading: Icon(icon, size: 20, color: DriftProTheme.primaryGreen),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      onTap: () {
        _addQuestionWithType(type);
      },
      hoverColor: DriftProTheme.primaryGreen.withOpacity(0.05),
    );
  }

  void _addQuestionWithType(SurveyQuestionType type) {
    setState(() {
      _questions.add(SurveyQuestion(
        id: const Uuid().v4(),
        surveyId: widget.survey.id,
        questionText: 'Nytt $type-spørsmål',
        type: type,
        isRequired: false,
        options: (type == SurveyQuestionType.single_choice || type == SurveyQuestionType.multiple_choice || type == SurveyQuestionType.dropdown)
            ? ['Alternativ 1', 'Alternativ 2']
            : [],
        orderIndex: _questions.length,
      ));
    });
  }

  Widget _buildSidebarToggle(String label, bool value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          SizedBox(
            height: 24,
            child: Switch.adaptive(value: value, activeColor: DriftProTheme.primaryGreen, onChanged: (v) {}),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvasHeader() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.business, color: DriftProTheme.primaryGreen, size: 40),
          const SizedBox(height: 24),
          TextFormField(
            initialValue: widget.survey.title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: DriftProTheme.primaryGreen),
            decoration: const InputDecoration(border: InputBorder.none, hintText: 'Tittel på undersøkelse'),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: widget.survey.description,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            decoration: const InputDecoration(border: InputBorder.none, hintText: 'Beskrivelse (valgfritt)'),
            maxLines: null,
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionsList() {
    return Column(
      children: [
        for (int i = 0; i < _questions.length; i++) _buildQuestionItem(i),
        const SizedBox(height: 20),
        _buildAddContentButton(),
      ],
    );
  }

  Widget _buildQuestionItem(int index) {
    final q = _questions[index];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(40),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.02) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: DriftProTheme.primaryGreen)),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: q.questionText,
                  decoration: const InputDecoration(border: InputBorder.none, hintText: 'Skriv spørsmålet ditt her...'),
                  onChanged: (val) {
                    _updateQuestion(index, SurveyQuestion(
                      id: q.id,
                      surveyId: q.surveyId,
                      questionText: val,
                      type: q.type,
                      isRequired: q.isRequired,
                      options: q.options,
                      orderIndex: q.orderIndex,
                    ));
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                onPressed: () => _removeQuestion(index),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildQuestionBody(index, q),
          const SizedBox(height: 20),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('Påkrevd', style: TextStyle(fontSize: 12)),
              Switch.adaptive(
                value: q.isRequired,
                activeColor: DriftProTheme.primaryGreen,
                onChanged: (val) {
                  _updateQuestion(index, SurveyQuestion(
                    id: q.id,
                    surveyId: q.surveyId,
                    questionText: q.questionText,
                    type: q.type,
                    isRequired: val,
                    options: q.options,
                    orderIndex: q.orderIndex,
                  ));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionBody(int index, SurveyQuestion q) {
    switch (q.type) {
      case SurveyQuestionType.single_choice:
      case SurveyQuestionType.multiple_choice:
      case SurveyQuestionType.dropdown:
        return Column(
          children: [
            for (int optIndex = 0; optIndex < q.options.length; optIndex++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(q.type == SurveyQuestionType.multiple_choice ? Icons.check_box_outline_blank : Icons.radio_button_off, size: 20, color: Colors.grey),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: q.options[optIndex],
                        decoration: const InputDecoration(border: InputBorder.none, hintText: 'Alternativ...'),
                        onChanged: (val) {
                          final newOpts = List<String>.from(q.options);
                          newOpts[optIndex] = val;
                          _updateQuestion(index, SurveyQuestion(
                            id: q.id,
                            surveyId: q.surveyId,
                            questionText: q.questionText,
                            type: q.type,
                            isRequired: q.isRequired,
                            options: newOpts,
                            orderIndex: q.orderIndex,
                          ));
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                      onPressed: () {
                        final newOpts = List<String>.from(q.options);
                        newOpts.removeAt(optIndex);
                        _updateQuestion(index, SurveyQuestion(
                          id: q.id,
                          surveyId: q.surveyId,
                          questionText: q.questionText,
                          type: q.type,
                          isRequired: q.isRequired,
                          options: newOpts,
                          orderIndex: q.orderIndex,
                        ));
                      },
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: () {
                final newOpts = List<String>.from(q.options);
                newOpts.add('Nytt alternativ');
                _updateQuestion(index, SurveyQuestion(
                  id: q.id,
                  surveyId: q.surveyId,
                  questionText: q.questionText,
                  type: q.type,
                  isRequired: q.isRequired,
                  options: newOpts,
                  orderIndex: q.orderIndex,
                ));
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Legg til alternativ'),
              style: TextButton.styleFrom(foregroundColor: DriftProTheme.primaryGreen),
            ),
          ],
        );
      case SurveyQuestionType.rating:
        return Row(
          children: List.generate(5, (i) => Icon(Icons.star_outline, color: Colors.grey[400], size: 32)),
        );
      case SurveyQuestionType.date:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
          child: const Row(
            children: [
              Icon(Icons.calendar_today, size: 18, color: Colors.grey),
              SizedBox(width: 12),
              Text('dd.mm.åååå', style: TextStyle(color: Colors.grey)),
            ],
          ),
        );
      case SurveyQuestionType.text:
      case SurveyQuestionType.paragraph:
      default:
        return Container(
          width: double.infinity,
          height: q.type == SurveyQuestionType.paragraph ? 100 : 50,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey[200]!), borderRadius: BorderRadius.circular(8)),
          child: Text(q.type == SurveyQuestionType.paragraph ? 'Lang tekstbeskrivelse...' : 'Kort tekstsvar...', style: const TextStyle(color: Colors.grey)),
        );
    }
  }

  Widget _buildAddContentButton() {
    return Center(
      child: ElevatedButton.icon(
        onPressed: _addQuestion,
        icon: const Icon(Icons.add),
        label: const Text('Legg til spørsmål'),
        style: ElevatedButton.styleFrom(
          backgroundColor: DriftProTheme.primaryGreen.withOpacity(0.1),
          foregroundColor: DriftProTheme.primaryGreen,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildCanvasFooter() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: const Border(top: BorderSide(color: Colors.black12)),
      ),
      child: Center(
        child: SizedBox(
          width: 200,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveChanges,
            style: ElevatedButton.styleFrom(
              backgroundColor: DriftProTheme.primaryGreen,
              padding: const EdgeInsets.symmetric(vertical: 20),
            ),
            child: _isSaving 
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text('LAGRE ENDRINGER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }
}
