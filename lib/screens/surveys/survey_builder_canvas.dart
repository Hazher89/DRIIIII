import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../models/survey/survey.dart';
import '../../core/services/survey/survey_service.dart';

class SurveyBuilderCanvas extends StatefulWidget {
  final Survey survey;
  /// Kalles etter vellykket lagring når brukeren trykker «Ferdig» (f.eks. gå til Publiser).
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

  /// Svært stort temautvalg (visuelt «studio») — hvert navn er et ferdig fargetema.
  static final Map<String, Color> _themeColors = {
    'Original': DriftProTheme.primaryGreen,
    'Enkelt': Colors.blueGrey,
    'Helfarget': Colors.indigo,
    'Skyskråper': Colors.blue,
    'Duggdråpe': Colors.teal,
    'Pastell': Colors.purpleAccent,
    'Midnatt': const Color(0xFF1A237E),
    'Skog': const Color(0xFF1B5E20),
    'Hav': const Color(0xFF006064),
    'Lava': const Color(0xFFBF360C),
    'Soloppgang': const Color(0xFFE65100),
    'Lavendel': const Color(0xFF6A1B9A),
    'Bær': const Color(0xFF880E4F),
    'Stål': const Color(0xFF455A64),
    'Isbre': const Color(0xFF4FC3F7),
    'Korall': const Color(0xFFFF7043),
    'Oliven': const Color(0xFF827717),
    'Monokrom': const Color(0xFF212121),
    'Sand': const Color(0xFFBCAAA4),
    'Neon lime': const Color(0xFF76FF03),
    'Magenta': const Color(0xFFC51162),
    'Turkis dyp': const Color(0xFF00838F),
    'Sapphire': const Color(0xFF0D47A1),
    'Amber': const Color(0xFFFFA000),
    'Jord': const Color(0xFF5D4037),
    'Granitt': const Color(0xFF37474F),
    'Petroleum': const Color(0xFF004D40),
    'Rose': const Color(0xFFAD1457),
    'Elektrisk blå': const Color(0xFF2962FF),
    'Vårgrønn': const Color(0xFF558B2F),
    'Twilight': const Color(0xFF4527A0),
    'Kobber': const Color(0xFFA1887F),
    'Arktisk blå': const Color(0xFF0277BD),
    'Rav': const Color(0xFFFF6F00),
    'Skifer': const Color(0xFF546E7A),
    'Drue': const Color(0xFF4A148C),
    'Mynte': const Color(0xFF00BFA5),
    'Rød alarm': const Color(0xFFC62828),
    'Profesjonell': const Color(0xFF263238),
    'Lys Nordic': const Color(0xFF90A4AE),
    'Emblem gull': const Color(0xFFF9A825),
    'Fjord': const Color(0xFF00897B),
    'Orchid': const Color(0xFFAB47BC),
    'Aske': const Color(0xFF757575),
    'Brand blå': const Color(0xFF1565C0),
    'Safety orange': const Color(0xFFE65100),
  };

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.survey.title);
    _descriptionController = TextEditingController(text: widget.survey.description);
    _allowAnonymous = widget.survey.allowAnonymous;
    _requireLogin = !widget.survey.allowAnonymous;
    _selectedTheme = widget.survey.theme;
    if (!_themeColors.containsKey(_selectedTheme)) _selectedTheme = 'Original';
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
    final List<String> options;
    switch (type) {
      case SurveyQuestionType.single_choice:
      case SurveyQuestionType.multiple_choice:
      case SurveyQuestionType.dropdown:
        options = ['Alternativ 1', 'Alternativ 2'];
        break;
      case SurveyQuestionType.likert:
        options = ['Helt uenig', 'Uenig', 'Nøytral', 'Enig', 'Helt enig'];
        break;
      case SurveyQuestionType.slider:
        options = ['0', '100'];
        break;
      default:
        options = <String>[];
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

  Future<bool> saveChanges() async {
    setState(() => _isSaving = true);
    try {
      // 1. Update survey header
      await SurveyService.updateSurvey(
        id: widget.survey.id,
        title: _titleController.text,
        description: _descriptionController.text,
        allowAnonymous: _allowAnonymous,
        theme: _selectedTheme,
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
            backgroundColor: _themeColors[_selectedTheme],
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
        _buildQuestionTypeItem(Icons.toggle_on_outlined, 'Ja/Nei', SurveyQuestionType.yes_no, themeColor),
        _buildQuestionTypeItem(Icons.pin_outlined, 'Tall', SurveyQuestionType.number, themeColor),
        _buildQuestionTypeItem(Icons.email_outlined, 'E-post', SurveyQuestionType.email, themeColor),
        _buildQuestionTypeItem(Icons.phone_outlined, 'Telefon', SurveyQuestionType.phone, themeColor),
        _buildQuestionTypeItem(Icons.insights_outlined, 'NPS (0-10)', SurveyQuestionType.nps, themeColor),
        _buildQuestionTypeItem(Icons.view_column_outlined, 'Likert-skala', SurveyQuestionType.likert, themeColor),
        _buildQuestionTypeItem(Icons.tune_outlined, 'Skyveknapp (tall)', SurveyQuestionType.slider, themeColor),
        _buildQuestionTypeItem(Icons.schedule_outlined, 'Klokkeslett', SurveyQuestionType.time, themeColor),
        _buildQuestionTypeItem(Icons.link_outlined, 'URL / lenke', SurveyQuestionType.url, themeColor),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: themeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Survey Builder V3 · fea1039',
              style: TextStyle(
                color: themeColor,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 16),
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
          _buildAdvancedRuleRow(index, q),
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
                      sectionTitle: q.sectionTitle,
                      points: q.points,
                      conditionQuestionId: q.conditionQuestionId,
                      conditionOperator: q.conditionOperator,
                      conditionValue: q.conditionValue,
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
      default:
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            _previewLabelForType(q.type),
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        );
    }
  }

  String _previewLabelForType(SurveyQuestionType type) {
    switch (type) {
      case SurveyQuestionType.text:
        return 'Kort tekstfelt';
      case SurveyQuestionType.paragraph:
        return 'Langt tekstfelt';
      case SurveyQuestionType.rating:
        return '1-5 stjerner';
      case SurveyQuestionType.date:
        return 'Dato-velger';
      case SurveyQuestionType.yes_no:
        return 'Ja/Nei bryter';
      case SurveyQuestionType.number:
        return 'Tallfelt med validering';
      case SurveyQuestionType.email:
        return 'E-postfelt med formatkontroll';
      case SurveyQuestionType.phone:
        return 'Telefonfelt';
      case SurveyQuestionType.nps:
        return 'NPS-skala 0-10';
      case SurveyQuestionType.single_choice:
      case SurveyQuestionType.multiple_choice:
      case SurveyQuestionType.dropdown:
        return 'Valg med alternativer';
      case SurveyQuestionType.likert:
        return 'Likert — rediger skalaetikketter';
      case SurveyQuestionType.slider:
        return 'Skyveknapp mellom min og maks';
      case SurveyQuestionType.time:
        return 'Velg klokkeslett (tidsvelger)';
      case SurveyQuestionType.url:
        return 'Lenke med formatkontroll';
    }
  }

  Widget _buildAdvancedRuleRow(int index, SurveyQuestion q) {
    final candidates =
        _questions.where((item) => item.orderIndex < q.orderIndex).toList();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        SizedBox(
          width: 140,
          child: TextFormField(
            initialValue: q.sectionTitle ?? '',
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Seksjon',
              border: OutlineInputBorder(),
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
                  sectionTitle: v.trim().isEmpty ? null : v.trim(),
                  points: q.points,
                  conditionQuestionId: q.conditionQuestionId,
                  conditionOperator: q.conditionOperator,
                  conditionValue: q.conditionValue,
                );
              });
            },
          ),
        ),
        SizedBox(
          width: 90,
          child: TextFormField(
            initialValue: q.points.toString(),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Poeng',
              border: OutlineInputBorder(),
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
                  points: (int.tryParse(v) ?? 0).clamp(0, 9999),
                  conditionQuestionId: q.conditionQuestionId,
                  conditionOperator: q.conditionOperator,
                  conditionValue: q.conditionValue,
                );
              });
            },
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String?>(
            value: q.conditionQuestionId,
            isDense: true,
            decoration: const InputDecoration(
              labelText: 'Synlig hvis spørsmål',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Ingen betingelse'),
              ),
              ...candidates.map(
                (item) => DropdownMenuItem<String?>(
                  value: item.id,
                  child: Text(
                    item.questionText,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
            ],
            onChanged: (value) {
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
                  conditionQuestionId: value,
                  conditionOperator: value == null ? null : (q.conditionOperator ?? 'equals'),
                  conditionValue: value == null ? null : q.conditionValue,
                );
              });
            },
          ),
        ),
      ],
    );
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
        const PopupMenuItem(value: SurveyQuestionType.date, child: Text('Dato')),
        const PopupMenuItem(value: SurveyQuestionType.yes_no, child: Text('Ja/Nei')),
        const PopupMenuItem(value: SurveyQuestionType.number, child: Text('Tall')),
        const PopupMenuItem(value: SurveyQuestionType.email, child: Text('E-post')),
        const PopupMenuItem(value: SurveyQuestionType.phone, child: Text('Telefon')),
        const PopupMenuItem(value: SurveyQuestionType.nps, child: Text('NPS (0-10)')),
        const PopupMenuItem(value: SurveyQuestionType.likert, child: Text('Likert-skala')),
        const PopupMenuItem(value: SurveyQuestionType.slider, child: Text('Skyveknapp')),
        const PopupMenuItem(value: SurveyQuestionType.time, child: Text('Klokkeslett')),
        const PopupMenuItem(value: SurveyQuestionType.url, child: Text('URL')),
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
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            children: [
              Text(
                'Neste steg: publiser og del lenke med respondenter',
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
                          'Ferdig — gå til Publiser',
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
