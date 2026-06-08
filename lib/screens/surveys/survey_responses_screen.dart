import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/survey/survey_analytics_engine.dart';
import '../../core/services/survey/survey_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/driftpro_theme_context.dart';
import '../../models/survey/survey.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Innboks med alle innsendte svar — filtrer og drill-down.
class SurveyResponsesScreen extends StatefulWidget {
  const SurveyResponsesScreen({super.key, required this.survey, this.embedded = false});

  final Survey survey;
  final bool embedded;

  @override
  State<SurveyResponsesScreen> createState() => _SurveyResponsesScreenState();
}

class _SurveyResponsesScreenState extends State<SurveyResponsesScreen> {
  bool _loading = true;
  List<SurveyQuestion> _questions = [];
  List<dynamic> _responses = [];
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final questions = await SurveyService.fetchQuestions(widget.survey.id);
      final results = await SurveyService.fetchResults(widget.survey.id);
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _responses = results['responses'] as List? ?? [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportCsv() async {
    final csv = SurveyAnalyticsEngine.exportCsv(
      survey: widget.survey,
      questions: _questions,
      rawResults: {'responses': _responses},
    );
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV kopiert til utklippstavle')),
    );
  }

  List<dynamic> get _filtered {
    if (_search.trim().isEmpty) return _responses;
    final q = _search.toLowerCase();
    return _responses.where((r) {
      final id = r['id'].toString().toLowerCase();
      final date = r['submitted_at'].toString().toLowerCase();
      return id.contains(q) || date.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;

    if (_loading) {
      return const DriftProLoadingCenter();
    }

    return Column(
      children: [
        if (!widget.embedded)
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            decoration: BoxDecoration(
              color: drift.card,
              border: Border(bottom: BorderSide(color: drift.borderSubtle)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Søk i svar (dato, ID…)',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: drift.surfaceMuted,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _exportCsv,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Eksporter CSV'),
                ),
                const SizedBox(width: 8),
                IconButton(tooltip: 'Oppdater', onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
        if (widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Søk svar…',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(onPressed: _exportCsv, icon: const Icon(Icons.download_outlined), tooltip: 'CSV'),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Oppdater'),
              ],
            ),
          ),
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined, size: 48, color: drift.textMuted),
                      const SizedBox(height: 12),
                      Text(
                        'Ingen svar ennå',
                        style: DriftProTheme.headingSm.copyWith(color: drift.textSecondary),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final resp = _filtered[index];
                    return _ResponseTile(
                      response: resp,
                      questions: _questions,
                      index: _responses.length - index,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ResponseTile extends StatefulWidget {
  const _ResponseTile({
    required this.response,
    required this.questions,
    required this.index,
  });

  final Map<String, dynamic> response;
  final List<SurveyQuestion> questions;
  final int index;

  @override
  State<_ResponseTile> createState() => _ResponseTileState();
}

class _ResponseTileState extends State<_ResponseTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final submitted = DateTime.tryParse(widget.response['submitted_at']?.toString() ?? '');
    final answers = widget.response['survey_answers'] as List? ?? [];
    final byQ = <String, dynamic>{};
    for (final a in answers) {
      byQ[a['question_id'] as String] = a['answer_value'];
    }

    return Material(
      color: drift.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: drift.borderSubtle),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                    child: Text(
                      '#${widget.index}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          submitted != null
                              ? '${submitted.day}.${submitted.month}.${submitted.year} ${submitted.hour.toString().padLeft(2, '0')}:${submitted.minute.toString().padLeft(2, '0')}'
                              : 'Ukjent tid',
                          style: DriftProTheme.labelMd.copyWith(color: drift.textPrimary),
                        ),
                        Text(
                          '${answers.length} av ${widget.questions.length} spørsmål besvart',
                          style: DriftProTheme.bodySm.copyWith(color: drift.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: drift.iconMuted),
                ],
              ),
              if (_expanded) ...[
                const Divider(height: 24),
                ...widget.questions.map((q) {
                  final val = byQ[q.id];
                  if (val == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          q.questionText,
                          style: DriftProTheme.bodySm.copyWith(
                            fontWeight: FontWeight.w600,
                            color: drift.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatVal(val),
                          style: DriftProTheme.bodyMd.copyWith(color: drift.textPrimary),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatVal(dynamic v) {
    if (v is Map) {
      return v.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    }
    if (v is List) return v.join(' → ');
    return v.toString();
  }
}
