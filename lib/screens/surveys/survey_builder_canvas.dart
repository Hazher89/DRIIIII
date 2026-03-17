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
  
  // Survey settings state
  late bool _allowAnonymous;
  late bool _requireLogin;
  DateTime? _expiresAt;

  // Theme presets
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
    _allowAnonymous = widget.survey.allowAnonymous;
    _requireLogin = !widget.survey.allowAnonymous;
    _expiresAt = widget.survey.expiresAt;
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addQuestion() {
    _addQuestionWithType(SurveyQuestionType.single_choice);
  }

  void _removeQuestion(int index) {
    setState(() {
      _questions.removeAt(index);
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
      // Logic to save survey settings (title, description, anonymous etc) would go here
      // For now we primarily save questions
      await SurveyService.saveQuestions(widget.survey.id, _questions);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Endringer lagret!'),
            backgroundColor: _themeColors[_selectedTheme],
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
          IconButton(
            icon: const Icon(Icons.help_outline, size: 16, color: Colors.grey),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.grey),
            onPressed: () {},
          ),
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
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? themeColor : Colors.grey,
          ),
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
        _buildSidebarToggle('Tidsfrist', _expiresAt != null, themeColor, (v) {
          setState(() {
            _expiresAt = v ? DateTime.now().add(const Duration(days: 7)) : null;
          });
        }),
      ],
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

  void _addQuestionWithType(SurveyQuestionType type) {
    setState(() {
      _questions.add(SurveyQuestion(
        id: const Uuid().v4(),
        surveyId: widget.survey.id,
        questionText: 'Nytt spørsmål',
        type: type,
        isRequired: false,
        options: (type == SurveyQuestionType.single_choice || type == SurveyQuestionType.multiple_choice || type == SurveyQuestionType.dropdown)
            ? ['Alternativ 1', 'Alternativ 2']
            : [],
        orderIndex: _questions.length,
      ));
    });
  }

  Widget _buildSidebarToggle(String label, bool value, Color themeColor, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          SizedBox(
            height: 24,
            child: Switch.adaptive(value: value, activeColor: themeColor, onChanged: (v) => onChanged(v)),
          ),
        ],
      ),
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
            initialValue: widget.survey.title,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: themeColor),
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

    return Container(
      padding: const EdgeInsets.all(32),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.02) : Colors.white,
        borderRadius: BorderRadius.circular(1), // Square look from image
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
                  initialValue: q.questionText,
                  style: const TextStyle(fontSize: 16),
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
                icon: const Icon(Icons.edit, size: 18, color: Colors.grey),
                onPressed: () {},
              )
            ],
          ),
          const SizedBox(height: 12),
          _buildQuestionBody(index, q, themeColor),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (q.isRequired) const Text('Påkrevd', style: TextStyle(fontSize: 11, color: Colors.red)),
              const Spacer(),
              IconButton(onPressed: () => _removeQuestion(index), icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildQuestionBody(int index, SurveyQuestion q, Color themeColor) {
    switch (q.type) {
      case SurveyQuestionType.single_choice:
      case SurveyQuestionType.multiple_choice:
      case SurveyQuestionType.dropdown:
        return Column(
          children: [
            for (int optIndex = 0; optIndex < q.options.length; optIndex++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(q.type == SurveyQuestionType.multiple_choice ? Icons.check_box_outline_blank : Icons.radio_button_off, size: 16, color: Colors.grey),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: q.options[optIndex],
                        style: const TextStyle(fontSize: 13),
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
                  ],
                ),
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
        child: Column(
          children: [
             SizedBox(
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
          ],
        ),
      ),
    );
  }
}
