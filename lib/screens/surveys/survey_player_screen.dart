import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/survey/survey.dart';
import '../../models/survey/survey_advanced.dart';
import '../../core/services/survey/survey_advanced_service.dart';
import '../../core/services/survey/survey_question_catalog.dart';
import '../../core/services/survey/survey_service.dart';
import '../../core/services/survey/survey_theme_presets.dart';
import '../../core/services/supabase_service.dart';
import '../../widgets/driftpro_loading_indicator.dart';

class SurveyPlayerScreen extends StatefulWidget {
  final String surveyId;
  final bool previewMode;

  const SurveyPlayerScreen({
    super.key,
    required this.surveyId,
    this.previewMode = false,
  });

  @override
  State<SurveyPlayerScreen> createState() => _SurveyPlayerScreenState();
}

class _SurveyPlayerScreenState extends State<SurveyPlayerScreen> {
  bool _isLoading = true;
  bool _isSubmitting = false;
  Survey? _survey;
  SurveyThemeConfig? _theme;
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
      final survey = await _fetchSurveyById(widget.surveyId.trim());
      final questions = await SurveyService.fetchQuestions(widget.surveyId);
      final theme = await SurveyAdvancedService.fetchTheme(widget.surveyId);
      
      setState(() {
        _survey = survey;
        _theme = theme;
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
    if (widget.previewMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preview-modus — svar lagres ikke')),
      );
      return;
    }
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

  Color _fromHex(String hex, Color fallback) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length != 6) return fallback;
    final value = int.tryParse('FF$cleaned', radix: 16);
    if (value == null) return fallback;
    return Color(value);
  }

  bool _isVisible(SurveyQuestion q) {
    final dep = q.conditionQuestionId;
    if (dep == null || dep.isEmpty) return true;
    final answer = _answers[dep];
    if (answer == null) return false;
    final expected = (q.conditionValue ?? '').trim().toLowerCase();
    if (expected.isEmpty) return true;
    final current = answer.toString().trim().toLowerCase();
    final op = q.conditionOperator ?? 'equals';
    return op == 'contains' ? current.contains(expected) : current == expected;
  }

  String _estimatedTime() {
    final mins = (_questions.length / 2).ceil().clamp(1, 30);
    return '$mins min';
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
      return const Scaffold(body: DriftProLoadingCenter());
    }

    if (_survey == null) {
      return const Scaffold(body: Center(child: Text('Undersøkelsen ble ikke funnet.')));
    }

    if (!widget.previewMode) {
      if (!_survey!.isActive) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'Denne undersøkelsen er lukket',
                    style: DriftProTheme.headingMd,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Den tar ikke lenger imot nye svar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      final expires = _survey!.expiresAt;
      if (expires != null && DateTime.now().isAfter(expires)) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event_busy_outlined, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'Undersøkelsen har utløpt',
                    style: DriftProTheme.headingMd,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Utløpsdato: ${expires.day}.${expires.month}.${expires.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    final preset = SurveyThemePresets.byNameOrDefault(_survey?.theme ?? 'DriftPro Grønn');
    final cfg = _theme ?? preset.toConfig(widget.surveyId);
    final primary = _fromHex(cfg.primaryHex, DriftProTheme.primaryGreen);
    final bg = _fromHex(cfg.backgroundHex, const Color(0xFFF7F9F8));
    final card = _fromHex(cfg.cardHex, Colors.white);
    final text = _fromHex(cfg.textHex, const Color(0xFF0F172A));
    final accent = _fromHex(cfg.accentHex, primary);
    final btnRadius = switch (cfg.buttonStyle) {
      'pill' => 28.0,
      'square' => 4.0,
      _ => 12.0,
    };
    final progress = _questions.isEmpty
        ? 0.0
        : _answers.length / _questions.where(_isVisible).length.clamp(1, 9999);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(_survey!.title, style: TextStyle(color: text, fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(decoration: _playerBackground(preset, bg, primary, accent)),
      ),
      body: Container(
        decoration: _playerBackground(preset, bg, primary, accent),
        child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (widget.previewMode)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.preview_outlined, color: Colors.amber),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Preview-modus — svar lagres ikke',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (cfg.showEstimatedTime)
                  Text(
                    'Estimert svartid: ${_estimatedTime()}',
                    style: TextStyle(color: text.withValues(alpha: 0.7)),
                  ),
                if (cfg.showProgressBar) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      color: primary,
                      backgroundColor: primary.withValues(alpha: 0.2),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (_survey!.description != null && _survey!.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: Text(
                      _survey!.description!,
                      style: TextStyle(fontSize: 16, color: text.withValues(alpha: 0.7)),
                    ),
                  ),
                ..._questions.where(_isVisible).map((q) => _buildQuestionWidget(q, primary, text, card, accent, preset, cfg.compactMode)),
                const SizedBox(height: 48),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(btnRadius)),
                      elevation: cfg.darkModeForRespondent ? 0 : 2,
                    ),
                    child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          widget.previewMode ? 'FORHÅNDSVIS SVAR' : 'SEND INN SVAR',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  BoxDecoration _playerBackground(SurveyThemePreset preset, Color bg, Color primary, Color accent) {
    switch (preset.visualStyle) {
      case SurveyVisualStyle.gradient:
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primary.withValues(alpha: 0.18), bg, accent.withValues(alpha: 0.12)],
          ),
        );
      case SurveyVisualStyle.glass:
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [primary.withValues(alpha: 0.25), bg],
          ),
        );
      case SurveyVisualStyle.neon:
        return BoxDecoration(color: bg);
      case SurveyVisualStyle.bold:
        return BoxDecoration(
          color: bg,
          border: Border(left: BorderSide(color: primary, width: 4)),
        );
      default:
        return BoxDecoration(color: bg);
    }
  }

  Widget _buildQuestionWidget(
    SurveyQuestion q,
    Color primary,
    Color textColor,
    Color cardColor,
    Color accent,
    SurveyThemePreset preset,
    bool compact,
  ) {
    final isGlass = preset.visualStyle == SurveyVisualStyle.glass;
    return Container(
      margin: EdgeInsets.only(bottom: compact ? 18 : 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isGlass ? cardColor.withValues(alpha: 0.72) : cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: preset.visualStyle == SurveyVisualStyle.bold ? 0.15 : 0.06),
            blurRadius: preset.visualStyle == SurveyVisualStyle.bold ? 12 : 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (q.sectionTitle != null && q.sectionTitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                q.sectionTitle!,
                style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  q.questionText,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                ),
              ),
              if (q.isRequired)
                Text(' *', style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: compact ? 8 : 16),
          _buildAnswerInput(q, primary, textColor, accent),
        ],
      ),
    );
  }

  Widget _buildAnswerInput(SurveyQuestion q, Color primary, Color textColor, Color accent) {
    switch (q.type) {
      case SurveyQuestionType.single_choice:
        return Column(
          children: q.options.map((opt) => RadioListTile<String>(
            title: Text(opt),
            value: opt,
            groupValue: _answers[q.id],
            activeColor: primary,
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
            activeColor: primary,
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
                color: primary,
                size: 40,
              ),
              onPressed: () => setState(() => _answers[q.id] = rating),
            );
          }),
        );
      case SurveyQuestionType.yes_no:
        return SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'yes', label: Text('Ja')),
            ButtonSegment(value: 'no', label: Text('Nei')),
          ],
          selected: {_answers[q.id]?.toString() ?? ''}..remove(''),
          onSelectionChanged: (sel) {
            if (sel.isNotEmpty) {
              setState(() => _answers[q.id] = sel.first);
            }
          },
          style: ButtonStyle(
            foregroundColor: WidgetStatePropertyAll(primary),
          ),
        );
      case SurveyQuestionType.number:
        return TextFormField(
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Skriv et tall',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (val) => _answers[q.id] = val,
        );
      case SurveyQuestionType.email:
        return TextFormField(
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: 'navn@firma.no',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (val) => _answers[q.id] = val,
        );
      case SurveyQuestionType.phone:
        return TextFormField(
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            hintText: '+47 900 00 000',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (val) => _answers[q.id] = val,
        );
      case SurveyQuestionType.nps:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(11, (index) {
            final selected = _answers[q.id] == index;
            return ChoiceChip(
              label: Text('$index'),
              selected: selected,
              selectedColor: primary.withValues(alpha: 0.2),
              onSelected: (_) => setState(() => _answers[q.id] = index),
            );
          }),
        );
      case SurveyQuestionType.dropdown:
        return DropdownButtonFormField<String>(
          value: _answers[q.id] as String?,
          items: q.options
              .map((o) => DropdownMenuItem<String>(value: o, child: Text(o)))
              .toList(),
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (val) => setState(() => _answers[q.id] = val),
        );
      case SurveyQuestionType.date:
        return TextButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              initialDate: DateTime.now(),
            );
            if (picked != null) {
              setState(() => _answers[q.id] = picked.toIso8601String());
            }
          },
          icon: const Icon(Icons.event),
          label: Text(
            _answers[q.id] == null ? 'Velg dato' : _answers[q.id].toString().split('T').first,
          ),
        );
      case SurveyQuestionType.likert:
        return Column(
          children: q.options.map((opt) => RadioListTile<String>(
            title: Text(opt),
            value: opt,
            groupValue: _answers[q.id],
            activeColor: primary,
            onChanged: (val) => setState(() => _answers[q.id] = val),
            contentPadding: EdgeInsets.zero,
          )).toList(),
        );
      case SurveyQuestionType.slider:
        final minVal = double.tryParse(q.options.isNotEmpty ? q.options[0] : '0') ?? 0;
        final maxVal = double.tryParse(q.options.length > 1 ? q.options[1] : '100') ?? 100;
        final span = maxVal - minVal;
        if (span <= 0) {
          return Text(
            'Skyveknapp er ikke konfigurert (min < maks).',
            style: TextStyle(color: Colors.red[700]),
          );
        }
        final current =
            ((_answers[q.id] as num?)?.toDouble()) ?? (minVal + span / 2);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Slider(
              value: current.clamp(minVal, maxVal),
              min: minVal,
              max: maxVal,
              activeColor: primary,
              onChanged: (v) => setState(() => _answers[q.id] = v),
            ),
            Text(
              'Verdi: ${current.clamp(minVal, maxVal).toStringAsFixed(2)}',
              style: TextStyle(color: textColor.withValues(alpha: 0.75)),
            ),
          ],
        );
      case SurveyQuestionType.time:
        return TextButton.icon(
          onPressed: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.now(),
            );
            if (picked != null) {
              final h = picked.hour.toString().padLeft(2, '0');
              final m = picked.minute.toString().padLeft(2, '0');
              setState(() => _answers[q.id] = '$h:$m');
            }
          },
          icon: const Icon(Icons.schedule),
          label: Text(_answers[q.id]?.toString() ?? 'Velg klokkeslett'),
        );
      case SurveyQuestionType.url:
        return TextFormField(
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'https://…',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (val) => _answers[q.id] = val,
          validator: q.isRequired
              ? (v) {
                  if (v == null || v.trim().isEmpty) return 'Vennligst fyll inn en lenke';
                  final u = Uri.tryParse(v.trim());
                  if (u == null || !(u.isScheme('http') || u.isScheme('https'))) {
                    return 'Oppgi en gyldig http(s)-lenke';
                  }
                  return null;
                }
              : (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final u = Uri.tryParse(v.trim());
                  if (u == null || !(u.isScheme('http') || u.isScheme('https'))) {
                    return 'Oppgi en gyldig http(s)-lenke';
                  }
                  return null;
                },
        );
      case SurveyQuestionType.matrix:
        final columns = SurveyQuestionCatalog.matrixColumns(q);
        _answers[q.id] ??= <String, String>{};
        final matrixAnswers = _answers[q.id] as Map<String, String>;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              const DataColumn(label: Text('')),
              ...columns.map((c) => DataColumn(label: Text(c))),
            ],
            rows: q.options.map((row) {
              return DataRow(
                cells: [
                  DataCell(Text(row, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ...columns.map((col) {
                    return DataCell(
                      Radio<String>(
                        value: col,
                        groupValue: matrixAnswers[row],
                        activeColor: primary,
                        onChanged: (val) {
                          setState(() => matrixAnswers[row] = val ?? '');
                        },
                      ),
                    );
                  }),
                ],
              );
            }).toList(),
          ),
        );
      case SurveyQuestionType.ranking:
        _answers[q.id] ??= List<String>.from(q.options);
        final ranked = List<String>.from(_answers[q.id] as List);
        return ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex -= 1;
              final item = ranked.removeAt(oldIndex);
              ranked.insert(newIndex, item);
              _answers[q.id] = ranked;
            });
          },
          children: ranked.asMap().entries.map((entry) {
            return ListTile(
              key: ValueKey('${q.id}_${entry.value}'),
              leading: CircleAvatar(
                backgroundColor: primary.withValues(alpha: 0.15),
                child: Text('${entry.key + 1}', style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
              ),
              title: Text(entry.value),
              trailing: const Icon(Icons.drag_handle),
            );
          }).toList(),
        );
    }
  }
}
