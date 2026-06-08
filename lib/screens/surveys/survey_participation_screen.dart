import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/survey/survey_service.dart';
import '../../models/survey/survey.dart';
import '../../core/services/supabase_service.dart';
import '../../widgets/driftpro_loading_indicator.dart';

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

  bool _isQuestionVisible(SurveyQuestion q) {
    final dependsOn = q.conditionQuestionId;
    if (dependsOn == null || dependsOn.isEmpty) return true;
    final triggerValue = _answers[dependsOn];
    if (triggerValue == null) return false;
    final expected = (q.conditionValue ?? '').trim().toLowerCase();
    if (expected.isEmpty) return true;
    final current = triggerValue.toString().trim().toLowerCase();
    final op = q.conditionOperator ?? 'equals';
    if (op == 'contains') {
      return current.contains(expected);
    }
    return current == expected;
  }

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
    final visibleQuestions = _questions.where(_isQuestionVisible).toList();
    for (var q in visibleQuestions) {
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
      final visibleAnswers = <String, dynamic>{};
      int totalScore = 0;
      int maxScore = 0;
      for (final q in visibleQuestions) {
        if (q.points > 0) {
          maxScore += q.points;
          final hasAnswer =
              _answers[q.id] != null && _answers[q.id].toString().trim().isNotEmpty;
          if (hasAnswer) {
            totalScore += q.points;
          }
        }
        if (_answers[q.id] != null) {
          visibleAnswers[q.id] = _answers[q.id];
        }
      }

      final responseId = await SurveyService.submitResponse(
        surveyId: widget.survey.id,
        userId: user?.id,
        answers: visibleAnswers,
      );
      await SurveyService.saveResponseScore(
        responseId: responseId,
        surveyId: widget.survey.id,
        totalScore: totalScore,
        maxScore: maxScore,
        answeredCount: visibleAnswers.length,
      );
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Takk!'),
            content: Text(
              maxScore > 0
                  ? 'Ditt svar har blitt registrert.\nPoeng: $totalScore / $maxScore'
                  : 'Ditt svar har blitt registrert.',
            ),
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
    if (_isLoading) return const Scaffold(body: DriftProLoadingCenter());

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
            ..._questions.where(_isQuestionVisible).map((q) => _buildQuestionWidget(q)),
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
        return Column(
          children: q.options.map((opt) {
            final selected = ((_answers[q.id] as List?) ?? const []).contains(opt);
            return CheckboxListTile(
              title: Text(opt),
              value: selected,
              onChanged: (checked) {
                final list = List<String>.from((_answers[q.id] as List?) ?? const []);
                if (checked == true) {
                  if (!list.contains(opt)) list.add(opt);
                } else {
                  list.remove(opt);
                }
                setState(() => _answers[q.id] = list);
              },
              controlAffinity: ListTileControlAffinity.leading,
            );
          }).toList(),
        );
      case SurveyQuestionType.dropdown:
      case SurveyQuestionType.single_choice:
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
        );
      case SurveyQuestionType.number:
        return TextField(
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Skriv et tall',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (v) => _answers[q.id] = v,
        );
      case SurveyQuestionType.email:
        return TextField(
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: 'E-postadresse',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (v) => _answers[q.id] = v,
        );
      case SurveyQuestionType.phone:
        return TextField(
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            hintText: 'Telefonnummer',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (v) => _answers[q.id] = v,
        );
      case SurveyQuestionType.nps:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(11, (index) {
            return ChoiceChip(
              label: Text('$index'),
              selected: _answers[q.id] == index,
              onSelected: (_) => setState(() => _answers[q.id] = index),
            );
          }),
        );
      case SurveyQuestionType.date:
        return TextButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              setState(() => _answers[q.id] = picked.toIso8601String());
            }
          },
          icon: const Icon(Icons.calendar_today),
          label: Text(
            _answers[q.id] == null ? 'Velg dato' : _answers[q.id].toString().split('T').first,
          ),
        );
      case SurveyQuestionType.rating:
        return Row(
          children: List.generate(5, (index) {
            final rating = index + 1;
            return IconButton(
              icon: Icon(
                rating <= ((_answers[q.id] as int?) ?? 0)
                    ? Icons.star
                    : Icons.star_outline,
                color: DriftProTheme.primaryGreen,
                size: 36,
              ),
              onPressed: () => setState(() => _answers[q.id] = rating),
            );
          }),
        );
      case SurveyQuestionType.likert:
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
      case SurveyQuestionType.slider:
        final minVal = double.tryParse(q.options.isNotEmpty ? q.options[0] : '0') ?? 0;
        final maxVal = double.tryParse(q.options.length > 1 ? q.options[1] : '100') ?? 100;
        final span = maxVal - minVal;
        if (span <= 0) {
          return Text(
            'Skyveknapp er ikke konfigurert (sett min < maks i redigering).',
            style: TextStyle(color: Colors.red[700]),
          );
        }
        final current = ((_answers[q.id] as num?)?.toDouble()) ?? (minVal + span / 2);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Slider(
              value: current.clamp(minVal, maxVal),
              min: minVal,
              max: maxVal,
              activeColor: DriftProTheme.primaryGreen,
              onChanged: (v) => setState(() => _answers[q.id] = v),
            ),
            Text(
              'Verdi: ${current.clamp(minVal, maxVal).toStringAsFixed(2)}',
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
        return TextField(
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'https://…',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (v) => _answers[q.id] = v,
        );
      case SurveyQuestionType.matrix:
      case SurveyQuestionType.ranking:
        return Text(
          'Spørsmålstypen støttes i den offentlige undersøkelseslenken.',
          style: TextStyle(color: Colors.grey[600]),
        );
    }
  }
}
