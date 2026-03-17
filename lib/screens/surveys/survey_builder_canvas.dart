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
  int _activeSideTab = 0; // 0 for Settings/Questions, 1 for Themes
  String _selectedTheme = 'Original';
  
  // Controllers for survey header
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  
  // Map to store controllers for questions and focus nodes
  final Map<String, TextEditingController> _questionControllers = {};
  final Map<String, FocusNode> _questionFocusNodes = {};
  final Map<String, List<TextEditingController>> _optionControllers = {};

  late bool _allowAnonymous;
  late bool _requireLogin;
  DateTime? _expiresAt;

  final Map<String, Color> _themeColors = {
    'Original': DriftProTheme.primaryGreen,
    'Enkelt': Colors.blueGrey,
    'Helfarget': Colors.indigo,
    'Skyskråper': Colors.blue,
    'Duggdråpe': Colors.teal,
    'Pastell': Colors.purpleAccent,
  };

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.survey.title);
    _descriptionController = TextEditingController(text: widget.survey.description);
    _allowAnonymous = widget.survey.allowAnonymous;
    _requireLogin = !widget.survey.allowAnonymous;
    _expiresAt = widget.survey.expiresAt;
    _loadQuestions();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    for (var c in _questionControllers.values) {
      c.dispose();
    }
    for (var f in _questionFocusNodes.values) {
      f.dispose();
    }
    for (var list in _optionControllers.values) {
      for (var c in list) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    setState(() => _isLoading = true);
    try {
      final questions = await SurveyService.fetchQuestions(widget.survey.id);
      
      // Initialize controllers for loaded questions
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addQuestionWithType(SurveyQuestionType type) {
    final id = const Uuid().v4();
    final options = (type == SurveyQuestionType.single_choice || type == SurveyQuestionType.multiple_choice || type == SurveyQuestionType.dropdown)
            ? ['Alternativ 1', 'Alternativ 2']
            : <String>[];
            
    _questionControllers[id] = TextEditingController(text: 'Nytt spørsmål');
    _questionFocusNodes[id] = FocusNode();
    _optionControllers[id] = options.map((opt) => TextEditingController(text: opt)).toList();

    setState(() {
      _questions.add(SurveyQuestion(
        id: id,
        surveyId: widget.survey.id,
        questionText: 'Nytt spørsmål',
        type: type,
        isRequired: false,
        options: options,
        orderIndex: _questions.length,
      ));
    });
    
    // Auto-focus the new question
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _questionFocusNodes[id]?.requestFocus();
    });
  }

  void _removeQuestion(int index) {
    final q = _questions[index];
    _questionControllers[q.id]?.dispose();
    _questionControllers.remove(q.id);
    _questionFocusNodes[q.id]?.dispose();
    _questionFocusNodes.remove(q.id);
    _optionControllers[q.id]?.forEach((c) => c.dispose());
    _optionControllers.remove(q.id);

    setState(() {
      _questions.removeAt(index);
      for (int i = 0; i < _questions.length; i++) {
        final currentQ = _questions[i];
        _questions[i] = SurveyQuestion(
          id: currentQ.id,
          surveyId: currentQ.surveyId,
          questionText: currentQ.questionText,
          type: currentQ.type,
          isRequired: currentQ.isRequired,
          options: currentQ.options,
          orderIndex: i,
        );
      }
    });
  }

  void _addOption(int qIndex) {
    final q = _questions[qIndex];
    final controller = TextEditingController(text: 'Nytt alternativ');
    setState(() {
      _optionControllers[q.id]?.add(controller);
      final newOpts = List<String>.from(q.options);
      newOpts.add('Nytt alternativ');
      _questions[qIndex] = SurveyQuestion(
        id: q.id,
        surveyId: q.surveyId,
        questionText: q.questionText,
        type: q.type,
        isRequired: q.isRequired,
        options: newOpts,
        orderIndex: q.orderIndex,
      );
    });
  }

  void _removeOption(int qIndex, int optIndex) {
    final q = _questions[qIndex];
    final controllers = _optionControllers[q.id];
    if (controllers != null && controllers.length > optIndex) {
      controllers[optIndex].dispose();
      controllers.removeAt(optIndex);
    }
    setState(() {
      final newOpts = List<String>.from(q.options);
      newOpts.removeAt(optIndex);
      _questions[qIndex] = SurveyQuestion(
        id: q.id,
        surveyId: q.surveyId,
        questionText: q.questionText,
        type: q.type,
        isRequired: q.isRequired,
        options: newOpts,
        orderIndex: q.orderIndex,
      );
    });
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      // 1. Update survey header
      await SurveyService.updateSurvey(
        id: widget.survey.id,
        title: _titleController.text,
        description: _descriptionController.text,
        allowAnonymous: _allowAnonymous,
      );

      // 2. Prepare questions with values from controllers
      final List<SurveyQuestion> updatedQuestions = [];
      for (int i = 0; i < _questions.length; i++) {
        final q = _questions[i];
        final textFromController = _questionControllers[q.id]?.text ?? q.questionText;
        final optionsFromControllers = _optionControllers[q.id]?.map((c) => c.text).toList() ?? q.options;
        
        updatedQuestions.add(SurveyQuestion(
          id: q.id,
          surveyId: q.surveyId,
          questionText: textFromController,
          type: q.type,
          isRequired: q.isRequired,
          options: optionsFromControllers,
          orderIndex: i,
        ));
      }

      // 3. Save questions and get updated data from DB
      final newQuestions = await SurveyService.saveQuestions(widget.survey.id, updatedQuestions);
      
      // 4. Sync state without destroying controllers
      setState(() {
        _questions = newQuestions;
        
        // Merge DB questions into our controller map
        for (var q in newQuestions) {
          if (!_questionControllers.containsKey(q.id)) {
            _questionControllers[q.id] = TextEditingController(text: q.questionText);
            _questionFocusNodes[q.id] = FocusNode();
          } else {
            // Update controller text IF it differs from current text (and current isn't being edited)
            if (_questionControllers[q.id]!.text != q.questionText) {
               _questionControllers[q.id]!.text = q.questionText;
            }
          }
          
          // Same for options
          if (!_optionControllers.containsKey(q.id) || _optionControllers[q.id]!.length != q.options.length) {
            _optionControllers[q.id] = q.options.map((opt) => TextEditingController(text: opt)).toList();
          }
        }
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Endringer lagret!'),
            backgroundColor: _themeColors[_selectedTheme],
            duration: const Duration(seconds: 2),
            action: SnackBarAction(label: 'OK', textColor: Colors.white, onPressed: () {}),
          ),
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
    final themeColor = _themeColors[_selectedTheme]!;

    return Row(
      children: [
        _buildSidebar(isDark, themeColor),
        Expanded(
          child: Container(
            color: isDark ? DriftProTheme.surfaceDark : const Color(0xFFF5F7F8),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                margin: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: isDark ? DriftProTheme.cardDark : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))
                  ],
                ),
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator())
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildCanvasHeader(themeColor),
                            _buildQuestionsList(isDark, themeColor),
                            const SizedBox(height: 40),
                            _buildCanvasFooter(themeColor),
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

  Widget _buildSidebar(bool isDark, Color themeColor) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        border: Border(right: BorderSide(color: isDark ? Colors.white10 : Colors.grey[200]!)),
      ),
      child: Column(
        children: [
          _buildSidebarTabs(isDark, themeColor),
          const Divider(height: 1),
          Expanded(
            child: _activeSideTab == 0 
                ? _buildSettingsContent(isDark, themeColor)
                : _buildThemesContent(isDark, themeColor),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarTabs(bool isDark, Color themeColor) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _buildTabItem(0, 'Innstillinger', themeColor),
          const SizedBox(width: 8),
          _buildTabItem(1, 'Temaer', themeColor),
          const Spacer(),
          IconButton(icon: const Icon(Icons.help_outline, size: 16), onPressed: () {}),
          IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }

  Widget _buildTabItem(int index, String label, Color themeColor) {
    final active = _activeSideTab == index;
    return InkWell(
      onTap: () => setState(() => _activeSideTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: active ? themeColor : Colors.transparent, width: 2)),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.bold : FontWeight.normal, color: active ? themeColor : Colors.grey),
        ),
      ),
    );
  }

  Widget _buildSettingsContent(bool isDark, Color themeColor) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('SPØRSMÅL-TYPER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 12),
        _buildQuestionTypeItem(Icons.radio_button_checked, 'Enkeltvalg', SurveyQuestionType.single_choice, themeColor),
        _buildQuestionTypeItem(Icons.check_box_outlined, 'Flervalg', SurveyQuestionType.multiple_choice, themeColor),
        _buildQuestionTypeItem(Icons.short_text, 'Kort tekst', SurveyQuestionType.text, themeColor),
        _buildQuestionTypeItem(Icons.notes, 'Lang tekst', SurveyQuestionType.paragraph, themeColor),
        _buildQuestionTypeItem(Icons.star_outline, 'Rangering', SurveyQuestionType.rating, themeColor),
        _buildQuestionTypeItem(Icons.calendar_today_outlined, 'Dato', SurveyQuestionType.date, themeColor),
        _buildQuestionTypeItem(Icons.arrow_drop_down_circle_outlined, 'Nedtrekk', SurveyQuestionType.dropdown, themeColor),
        const SizedBox(height: 32),
        const Text('INNSTILLINGER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 12),
        _buildSidebarToggle('Anonyme svar', _allowAnonymous, themeColor, (v) => setState(() {
          _allowAnonymous = v;
          if (v) _requireLogin = false;
        })),
        _buildSidebarToggle('Krev pålogging', _requireLogin, themeColor, (v) => setState(() {
          _requireLogin = v;
          if (v) _allowAnonymous = false;
        })),
      ],
    );
  }

  Widget _buildSidebarToggle(String label, bool value, Color themeColor, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          SizedBox(height: 24, child: Switch.adaptive(value: value, activeColor: themeColor, onChanged: (v) => onChanged(v))),
        ],
      ),
    );
  }

  Widget _buildThemesContent(bool isDark, Color themeColor) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: _themeColors.keys.map((name) {
        final color = _themeColors[name]!;
        final selected = _selectedTheme == name;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () => setState(() => _selectedTheme = name),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: selected ? color : Colors.grey[200]!, width: selected ? 2 : 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(width: 40, height: 24, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 12),
                  Text(name, style: const TextStyle(fontSize: 13)),
                  const Spacer(),
                  if (selected) Icon(Icons.check, size: 16, color: color),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildQuestionTypeItem(IconData icon, String label, SurveyQuestionType type, Color themeColor) {
    return ListTile(
      leading: Icon(icon, size: 20, color: themeColor),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      onTap: () => _addQuestionWithType(type),
      contentPadding: EdgeInsets.zero,
      dense: true,
      hoverColor: themeColor.withOpacity(0.05),
    );
  }

  Widget _buildCanvasHeader(Color themeColor) {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.business, color: themeColor, size: 40),
              const SizedBox(width: 12),
              Text('DIN LOGO HER', style: TextStyle(color: Colors.grey[400], fontSize: 13, letterSpacing: 1.2)),
            ],
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _titleController,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: themeColor),
            decoration: const InputDecoration(border: InputBorder.none, hintText: 'Tittel på undersøkelse'),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _descriptionController,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            decoration: const InputDecoration(border: InputBorder.none, hintText: 'Beskrivelse (valgfritt)'),
            maxLines: null,
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionsList(bool isDark, Color themeColor) {
    return Column(
      children: [
        for (int i = 0; i < _questions.length; i++) _buildQuestionItem(i, isDark, themeColor),
        const SizedBox(height: 20),
        _buildCentralAddButton(isDark, themeColor),
      ],
    );
  }

  Widget _buildQuestionItem(int index, bool isDark, Color themeColor) {
    final q = _questions[index];
    final controller = _questionControllers[q.id];
    final focusNode = _questionFocusNodes[q.id];

    return Container(
      padding: const EdgeInsets.all(32),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.02) : Colors.white,
        border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey[100]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${index + 1}. ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Expanded(
                child: TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(border: InputBorder.none, hintText: 'Skriv spørsmålet ditt her...'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 18, color: Colors.grey),
                onPressed: () => focusNode?.requestFocus(),
              )
            ],
          ),
          const SizedBox(height: 12),
          _buildQuestionBody(index, q, themeColor),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('Påkrevd', style: TextStyle(fontSize: 12)),
              Switch.adaptive(
                value: q.isRequired,
                activeColor: themeColor,
                onChanged: (v) {
                  setState(() {
                    _questions[index] = SurveyQuestion(
                      id: q.id,
                      surveyId: q.surveyId,
                      questionText: q.questionText,
                      type: q.type,
                      isRequired: v,
                      options: q.options,
                      orderIndex: q.orderIndex,
                    );
                  });
                },
              ),
              const Spacer(),
              IconButton(onPressed: () => _removeQuestion(index), icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildQuestionBody(int index, SurveyQuestion q, Color themeColor) {
    final controllers = _optionControllers[q.id] ?? [];
    
    switch (q.type) {
      case SurveyQuestionType.single_choice:
      case SurveyQuestionType.multiple_choice:
      case SurveyQuestionType.dropdown:
        return Column(
          children: [
            for (int optIndex = 0; optIndex < controllers.length; optIndex++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(q.type == SurveyQuestionType.multiple_choice ? Icons.check_box_outline_blank : Icons.radio_button_off, size: 16, color: Colors.grey),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: controllers[optIndex],
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(border: InputBorder.none, hintText: 'Alternativ...'),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.close, size: 14), onPressed: () => _removeOption(index, optIndex)),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: () => _addOption(index),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Legg til alternativ', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: themeColor),
            ),
          ],
        );
      default:
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Type: ${q.type.name.toUpperCase()}', style: TextStyle(color: Colors.grey[400], fontSize: 11)),
        );
    }
  }

  Widget _buildCentralAddButton(bool isDark, Color themeColor) {
    return PopupMenuButton<SurveyQuestionType>(
      tooltip: 'Legg til innhold',
      offset: const Offset(0, 40),
      onSelected: (type) => _addQuestionWithType(type),
      itemBuilder: (context) => [
        const PopupMenuItem(value: SurveyQuestionType.single_choice, child: Text('Enkeltvalg')),
        const PopupMenuItem(value: SurveyQuestionType.multiple_choice, child: Text('Flervalg')),
        const PopupMenuItem(value: SurveyQuestionType.text, child: Text('Kort tekst')),
        const PopupMenuItem(value: SurveyQuestionType.paragraph, child: Text('Lang tekst')),
        const PopupMenuItem(value: SurveyQuestionType.rating, child: Text('Rangering')),
      ],
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: themeColor, shape: BoxShape.circle),
        child: const Icon(Icons.add, color: Colors.white, size: 32),
      ),
    );
  }

  Widget _buildCanvasFooter(Color themeColor) {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: SizedBox(
          width: 120,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveChanges,
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isSaving 
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Ferdig', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }
}
