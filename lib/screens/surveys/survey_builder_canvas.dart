import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../models/survey/survey.dart';
import '../../core/services/survey/survey_advanced_service.dart';
import '../../core/services/survey/survey_question_catalog.dart';
import '../../core/services/survey/survey_service.dart';
import '../../core/services/survey/survey_theme_presets.dart';

class SurveyBuilderCanvas extends StatefulWidget {
  final Survey survey;
  /// Kalles etter vellykket lagring når brukeren trykker «Ferdig» (går til Tema).
  final VoidCallback? onAfterSuccessfulSave;

  const SurveyBuilderCanvas({
    super.key,
    required this.survey,
    this.onAfterSuccessfulSave,
  });

  @override
  State<SurveyBuilderCanvas> createState() => SurveyBuilderCanvasState();
}

class SurveyBuilderCanvasState extends State<SurveyBuilderCanvas> {
  bool _isLoading = true;
  bool _isSaving = false;
  List<SurveyQuestion> _questions = [];
  int _activeSideTab = 0;
  String _selectedTheme = 'DriftPro Grønn';
  String _themeSearch = '';
  final Set<String> _advancedOpen = {};
  
  // Controllers for survey header
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _notesController;
  
  // Map to store controllers for questions and focus nodes
  final Map<String, TextEditingController> _questionControllers = {};
  final Map<String, FocusNode> _questionFocusNodes = {};
  final Map<String, List<TextEditingController>> _optionControllers = {};

  late bool _allowAnonymous;
  late bool _requireLogin;
  DateTime? _expiresAt;

  SurveyThemePreset get _activePreset => SurveyThemePresets.byNameOrDefault(_selectedTheme);

  Color _colorFromHex(String hex, [Color fallback = DriftProTheme.primaryGreen]) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length != 6) return fallback;
    final value = int.tryParse('FF$cleaned', radix: 16);
    return value != null ? Color(value) : fallback;
  }

  void _patchQuestion(int index, SurveyQuestion Function(SurveyQuestion q) patch) {
    setState(() => _questions[index] = patch(_questions[index]));
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.survey.title);
    _descriptionController = TextEditingController(text: widget.survey.description);
    _notesController = TextEditingController(text: widget.survey.adminNotes ?? '');
    _allowAnonymous = widget.survey.allowAnonymous;
    _requireLogin = !widget.survey.allowAnonymous;
    _selectedTheme = SurveyThemePresets.byNameOrDefault(widget.survey.theme).name;
    _expiresAt = widget.survey.expiresAt;
    _loadQuestions();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
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
    final def = SurveyQuestionCatalog.defFor(type);
    final options = def?.defaultOptions.isNotEmpty == true
        ? List<String>.from(def!.defaultOptions)
        : <String>[];
    String? conditionValue;
    if (type == SurveyQuestionType.matrix) {
      conditionValue = def?.defaultConditionValue ?? 'Dårlig|Middels|Bra|Utmerket';
    }
            
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
        conditionValue: conditionValue,
      ));
    });
    
    // Auto-focus the new question
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _questionFocusNodes[id]?.requestFocus();
    });
  }

  void _changeQuestionType(int index, SurveyQuestionType type) {
    final old = _questions[index];
    final def = SurveyQuestionCatalog.defFor(type);
    final options = def?.defaultOptions.isNotEmpty == true
        ? List<String>.from(def!.defaultOptions)
        : <String>[];
    _optionControllers[old.id]?.forEach((c) => c.dispose());
    _optionControllers[old.id] = options.map((o) => TextEditingController(text: o)).toList();
    setState(() {
      _questions[index] = SurveyQuestion(
        id: old.id,
        surveyId: old.surveyId,
        questionText: old.questionText,
        type: type,
        isRequired: old.isRequired,
        options: options,
        orderIndex: old.orderIndex,
        sectionTitle: old.sectionTitle,
        points: old.points,
        conditionQuestionId: old.conditionQuestionId,
        conditionOperator: old.conditionOperator,
        conditionValue: type == SurveyQuestionType.matrix
            ? (def?.defaultConditionValue ?? 'Dårlig|Middels|Bra|Utmerket')
            : old.conditionValue,
      );
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

  Future<bool> saveChanges() async {
    setState(() => _isSaving = true);
    try {
      // 1. Update survey header
      await SurveyService.updateSurvey(
        id: widget.survey.id,
        title: _titleController.text,
        description: _descriptionController.text,
        allowAnonymous: _allowAnonymous,
        theme: _activePreset.name,
        adminNotes: _notesController.text.trim(),
      );
      await SurveyAdvancedService.upsertTheme(
        _activePreset.toConfig(widget.survey.id),
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
          sectionTitle: q.sectionTitle,
          points: q.points,
          conditionQuestionId: q.conditionQuestionId,
          conditionOperator: q.conditionOperator,
          conditionValue: q.conditionValue,
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
            backgroundColor: _colorFromHex(_activePreset.primaryHex),
            duration: const Duration(seconds: 2),
            action: SnackBarAction(label: 'OK', textColor: Colors.white, onPressed: () {}),
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke lagre: $e'), backgroundColor: Colors.red),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _finishAndProceed() async {
    final ok = await saveChanges();
    if (!mounted || !ok) return;
    widget.onAfterSuccessfulSave?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final preset = _activePreset;
    final themeColor = _colorFromHex(preset.primaryHex);
    final canvasBg = _colorFromHex(preset.backgroundHex);
    final cardBg = _colorFromHex(preset.cardHex);

    return Row(
      children: [
        _buildSidebar(isDark, themeColor),
        Expanded(
          child: Container(
            color: canvasBg,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                margin: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: preset.darkMode ? 0.4 : 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
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
      padding: const EdgeInsets.all(16),
      children: [
        for (final group in SurveyQuestionCatalog.groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(
              group.toUpperCase(),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[600], letterSpacing: 0.6),
            ),
          ),
          ...SurveyQuestionCatalog.all.where((d) => d.group == group).map(
                (def) => _buildQuestionTypeItem(def.icon, def.label, def.type, themeColor, def.description),
              ),
        ],
        const SizedBox(height: 20),
        const Text('INNSTILLINGER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
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
    final q = _themeSearch.trim().toLowerCase();
    final filtered = SurveyThemePresets.all.where((t) {
      if (q.isEmpty) return true;
      return t.name.toLowerCase().contains(q) || t.category.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Søk blant ${SurveyThemePresets.all.length} tema…',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (v) => setState(() => _themeSearch = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '${filtered.length} tema — endrer bakgrunn, kort, knapper og tekst for respondenter',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: filtered.length,
            itemBuilder: (context, i) {
              final preset = filtered[i];
              final selected = _selectedTheme == preset.name;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => setState(() => _selectedTheme = preset.name),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: selected ? themeColor : Colors.grey[300]!,
                        width: selected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      color: _colorFromHex(preset.backgroundHex),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 32,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: _colorFromHex(preset.cardHex),
                            border: Border.all(color: _colorFromHex(preset.primaryHex), width: 2),
                          ),
                          child: Center(
                            child: Container(
                              width: 20,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _colorFromHex(preset.primaryHex),
                                borderRadius: BorderRadius.circular(preset.buttonStyle == 'pill' ? 8 : 2),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(preset.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              Text(preset.category, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                            ],
                          ),
                        ),
                        if (selected) Icon(Icons.check_circle, size: 18, color: themeColor),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionTypeItem(
    IconData icon,
    String label,
    SurveyQuestionType type,
    Color themeColor, [
    String? subtitle,
  ]) {
    return ListTile(
      leading: Icon(icon, size: 20, color: themeColor),
      title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey[600])) : null,
      onTap: () => _addQuestionWithType(type),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
      hoverColor: themeColor.withValues(alpha: 0.06),
    );
  }

  Widget _buildCanvasHeader(Color themeColor) {
    final preset = _activePreset;
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.business, color: themeColor, size: 36),
              const SizedBox(width: 12),
              Text('LOGO', style: TextStyle(color: Colors.grey[400], fontSize: 12, letterSpacing: 1.2)),
            ],
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _titleController,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: themeColor),
            decoration: const InputDecoration(border: InputBorder.none, hintText: 'Tittel på undersøkelsen'),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _descriptionController,
            style: TextStyle(fontSize: 15, color: _colorFromHex(preset.textHex).withValues(alpha: 0.7)),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Beskrivelse til respondentene (valgfritt)',
            ),
            maxLines: null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _notesController,
            style: TextStyle(fontSize: 13, color: Colors.grey[600], fontStyle: FontStyle.italic),
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              hintText: 'Interne notater (kun for deg — vises ikke for respondenter)',
              prefixIcon: Icon(Icons.sticky_note_2_outlined, size: 18, color: Colors.grey[500]),
              isDense: true,
              filled: true,
              fillColor: Colors.amber.withValues(alpha: 0.06),
            ),
            maxLines: 2,
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
    final typeDef = SurveyQuestionCatalog.defFor(q.type);
    final advancedOpen = _advancedOpen.contains(q.id);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: themeColor.withValues(alpha: 0.12),
                child: Text('${index + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: themeColor)),
              ),
              const SizedBox(width: 10),
              PopupMenuButton<SurveyQuestionType>(
                tooltip: 'Endre type',
                onSelected: (type) => _changeQuestionType(index, type),
                itemBuilder: (_) => SurveyQuestionCatalog.all
                    .map((d) => PopupMenuItem(value: d.type, child: Text(d.label)))
                    .toList(),
                child: Chip(
                  avatar: Icon(typeDef?.icon ?? Icons.help_outline, size: 16, color: themeColor),
                  label: Text(typeDef?.label ?? q.type.name, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                tooltip: 'Slett spørsmål',
                onPressed: () => _removeQuestion(index),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: controller,
            focusNode: focusNode,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Skriv spørsmålet her…',
            ),
          ),
          const SizedBox(height: 8),
          _buildQuestionBody(index, q, themeColor),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch.adaptive(
                value: q.isRequired,
                activeTrackColor: themeColor.withValues(alpha: 0.4),
                activeThumbColor: themeColor,
                onChanged: (v) => _patchQuestion(index, (old) => SurveyQuestion(
                  id: old.id,
                  surveyId: old.surveyId,
                  questionText: old.questionText,
                  type: old.type,
                  isRequired: v,
                  options: old.options,
                  orderIndex: old.orderIndex,
                  sectionTitle: old.sectionTitle,
                  points: old.points,
                  conditionQuestionId: old.conditionQuestionId,
                  conditionOperator: old.conditionOperator,
                  conditionValue: old.conditionValue,
                )),
              ),
              const Text('Påkrevd', style: TextStyle(fontSize: 12)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() {
                  if (advancedOpen) {
                    _advancedOpen.remove(q.id);
                  } else {
                    _advancedOpen.add(q.id);
                  }
                }),
                icon: Icon(advancedOpen ? Icons.expand_less : Icons.tune, size: 16),
                label: Text(advancedOpen ? 'Skjul avansert' : 'Avansert (valgfritt)', style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (advancedOpen) ...[
            const Divider(height: 16),
            _buildAdvancedSection(index, q, themeColor),
          ],
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
      case SurveyQuestionType.likert:
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
      case SurveyQuestionType.slider:
        if (controllers.length < 2) {
          return Text(
            'Skyveknapp krever min og maks',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: controllers[0],
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Min',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: controllers[1],
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Maks',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Forhåndsvisning: kontinuerlig skyver (svaret lagres som tall)',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        );
      case SurveyQuestionType.matrix:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rader (uttalelser)', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(height: 8),
            for (int optIndex = 0; optIndex < controllers.length; optIndex++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.drag_indicator, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: controllers[optIndex],
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Rad…',
                        ),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.close, size: 14), onPressed: () => _removeOption(index, optIndex)),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: () => _addOption(index),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Legg til rad', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: themeColor),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: q.conditionValue ?? 'Dårlig|Middels|Bra|Utmerket',
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Kolonner (skill med |)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) {
                setState(() {
                  _questions[index] = SurveyQuestion(
                    id: q.id,
                    surveyId: q.surveyId,
                    questionText: q.questionText,
                    type: q.type,
                    isRequired: q.isRequired,
                    options: q.options,
                    orderIndex: q.orderIndex,
                    sectionTitle: q.sectionTitle,
                    points: q.points,
                    conditionQuestionId: q.conditionQuestionId,
                    conditionOperator: q.conditionOperator,
                    conditionValue: v.trim(),
                  );
                });
              },
            ),
          ],
        );
      case SurveyQuestionType.ranking:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Elementer som skal rangeres', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(height: 8),
            for (int optIndex = 0; optIndex < controllers.length; optIndex++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Text('${optIndex + 1}.', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: controllers[optIndex],
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Alternativ…',
                        ),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.close, size: 14), onPressed: () => _removeOption(index, optIndex)),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: () => _addOption(index),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Legg til element', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: themeColor),
            ),
          ],
        );
      default:
        return _buildTypePreview(q, themeColor);
    }
  }

  Widget _buildTypePreview(SurveyQuestion q, Color themeColor) {
    switch (q.type) {
      case SurveyQuestionType.rating:
        return Row(
          children: List.generate(5, (i) => Icon(Icons.star, color: themeColor.withValues(alpha: 0.35 + i * 0.1), size: 28)),
        );
      case SurveyQuestionType.yes_no:
        return Row(
          children: [
            _previewChip('Ja', themeColor),
            const SizedBox(width: 8),
            _previewChip('Nei', themeColor, filled: false),
          ],
        );
      case SurveyQuestionType.nps:
        return Wrap(
          spacing: 4,
          children: List.generate(11, (i) => _previewChip('$i', themeColor, small: true)),
        );
      case SurveyQuestionType.date:
        return _previewChip('📅 Velg dato', themeColor, filled: false);
      case SurveyQuestionType.time:
        return _previewChip('🕐 Velg klokkeslett', themeColor, filled: false);
      case SurveyQuestionType.text:
        return Container(
          height: 40,
          decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('Kort tekstsvar…', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
        );
      case SurveyQuestionType.paragraph:
        return Container(
          height: 80,
          decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.topLeft,
          padding: const EdgeInsets.all(12),
          child: Text('Langt svar / kommentar…', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
        );
      case SurveyQuestionType.number:
      case SurveyQuestionType.email:
      case SurveyQuestionType.phone:
      case SurveyQuestionType.url:
        return Container(
          height: 40,
          decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(SurveyQuestionCatalog.labelFor(q.type), style: TextStyle(color: Colors.grey[500], fontSize: 13)),
        );
      default:
        return Text(
          SurveyQuestionCatalog.labelFor(q.type),
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        );
    }
  }

  Widget _previewChip(String label, Color color, {bool filled = true, bool small = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 14, vertical: small ? 4 : 8),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.15) : Colors.transparent,
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(small ? 6 : 20),
      ),
      child: Text(label, style: TextStyle(fontSize: small ? 11 : 13, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildAdvancedSection(int index, SurveyQuestion q, Color themeColor) {
    final candidates = _questions.where((item) => item.orderIndex < q.orderIndex).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Avanserte innstillinger — de fleste trenger ikke disse.',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: q.sectionTitle ?? '',
          decoration: const InputDecoration(
            labelText: 'Seksjon / overskrift',
            helperText: 'Grupper spørsmål under en felles overskrift (f.eks. «Om deg», «Tilfredshet»)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => _patchQuestion(index, (old) => SurveyQuestion(
            id: old.id,
            surveyId: old.surveyId,
            questionText: old.questionText,
            type: old.type,
            isRequired: old.isRequired,
            options: old.options,
            orderIndex: old.orderIndex,
            sectionTitle: v.trim().isEmpty ? null : v.trim(),
            points: old.points,
            conditionQuestionId: old.conditionQuestionId,
            conditionOperator: old.conditionOperator,
            conditionValue: old.conditionValue,
          )),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: q.conditionQuestionId,
          decoration: const InputDecoration(
            labelText: 'Vis bare hvis…',
            helperText: 'Spørsmålet vises kun når et tidligere spørsmål har bestemt svar',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('Alltid synlig')),
            ...candidates.map(
              (item) => DropdownMenuItem(
                value: item.id,
                child: Text(item.questionText, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (value) => _patchQuestion(index, (old) => SurveyQuestion(
            id: old.id,
            surveyId: old.surveyId,
            questionText: old.questionText,
            type: old.type,
            isRequired: old.isRequired,
            options: old.options,
            orderIndex: old.orderIndex,
            sectionTitle: old.sectionTitle,
            points: old.points,
            conditionQuestionId: value,
            conditionOperator: value == null ? null : (old.conditionOperator ?? 'equals'),
            conditionValue: value == null ? null : old.conditionValue,
          )),
        ),
      ],
    );
  }

  Widget _buildCentralAddButton(bool isDark, Color themeColor) {
    return PopupMenuButton<SurveyQuestionType>(
      tooltip: 'Legg til innhold',
      offset: const Offset(0, 40),
      onSelected: (type) => _addQuestionWithType(type),
      itemBuilder: (context) {
        final items = <PopupMenuEntry<SurveyQuestionType>>[];
        for (final group in SurveyQuestionCatalog.groups) {
          items.add(PopupMenuItem<SurveyQuestionType>(
            enabled: false,
            child: Text(
              group,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
                letterSpacing: 0.5,
              ),
            ),
          ));
          for (final def in SurveyQuestionCatalog.all.where((d) => d.group == group)) {
            items.add(PopupMenuItem(
              value: def.type,
              child: Row(
                children: [
                  Icon(def.icon, size: 18, color: themeColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(def.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(def.description, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                ],
              ),
            ));
          }
        }
        return items;
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: themeColor, shape: BoxShape.circle),
        child: const Icon(Icons.add, color: Colors.white, size: 32),
      ),
    );
  }

  Widget _buildCanvasFooter(Color themeColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            children: [
              Text(
                'Neste steg: velg tema for respondentene',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _finishAndProceed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Ferdig — gå til Tema',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
