import 'package:flutter/material.dart';

import '../../core/services/survey/survey_analytics_engine.dart';
import '../../core/services/survey/survey_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/driftpro_theme_context.dart';
import '../../models/survey/survey.dart';

/// Dashboard for én undersøkelse — KPI, spørsmål, hurtighandlinger.
class SurveyOverviewPanel extends StatefulWidget {
  const SurveyOverviewPanel({
    super.key,
    required this.survey,
    required this.onGoToStep,
  });

  final Survey survey;
  final void Function(int step) onGoToStep;

  @override
  State<SurveyOverviewPanel> createState() => _SurveyOverviewPanelState();
}

class _SurveyOverviewPanelState extends State<SurveyOverviewPanel> {
  bool _loading = true;
  int _questionCount = 0;
  SurveySummaryMetrics? _metrics;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final questions = await SurveyService.fetchQuestions(widget.survey.id);
      final results = await SurveyService.fetchResults(widget.survey.id);
      final metrics = SurveyAnalyticsEngine.computeSummary(
        questions: questions,
        rawResults: results,
      );
      if (!mounted) return;
      setState(() {
        _questionCount = questions.length;
        _metrics = metrics;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final m = _metrics;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: drift.heroGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: drift.elevatedShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.survey.title,
                style: DriftProTheme.headingLg.copyWith(color: Colors.white),
              ),
              if (widget.survey.description != null &&
                  widget.survey.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  widget.survey.description!,
                  style: DriftProTheme.bodyMd.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(
                    widget.survey.isActive ? 'Åpen for svar' : 'Lukket',
                    widget.survey.isActive ? Colors.greenAccent : Colors.orangeAccent,
                  ),
                  _chip('$_questionCount spørsmål', Colors.white70),
                  _chip(
                    widget.survey.allowAnonymous ? 'Anonym' : 'Krever innlogging',
                    Colors.white70,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth > 700;
            final cards = [
              _KpiCard(
                label: 'Totalt svar',
                value: '${m?.totalResponses ?? 0}',
                icon: Icons.people_outline,
                color: Colors.blue,
              ),
              _KpiCard(
                label: 'Fullføringsgrad',
                value: m != null ? '${m.completionRate.toStringAsFixed(0)}%' : '—',
                icon: Icons.check_circle_outline,
                color: Colors.green,
              ),
              _KpiCard(
                label: 'Snittid',
                value: m?.formattedDuration ?? '—',
                icon: Icons.timer_outlined,
                color: Colors.orange,
              ),
              if (m?.npsScore != null)
                _KpiCard(
                  label: 'NPS-score',
                  value: m!.npsScore!.toStringAsFixed(0),
                  icon: Icons.insights_outlined,
                  color: Colors.purple,
                ),
            ];
            if (wide) {
              return Row(
                children: cards
                    .map((c) => Expanded(child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: c,
                        )))
                    .toList(),
              );
            }
            return Column(
              children: cards.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: c,
                  )).toList(),
            );
          },
        ),
        const SizedBox(height: 24),
        Text(
          'Hurtighandlinger',
          style: DriftProTheme.headingSm.copyWith(color: drift.textPrimary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _action(context, Icons.edit_note, 'Bygg spørsmål', 1),
            _action(context, Icons.share_outlined, 'Del lenke', 2),
            _action(context, Icons.inbox_outlined, 'Se alle svar', 3),
            _action(context, Icons.bar_chart, 'Statistikk', 4),
            _action(context, Icons.palette_outlined, 'Tema & arkiv', 5),
          ],
        ),
      ],
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _action(BuildContext context, IconData icon, String label, int step) {
    final drift = context.driftColors;
    return Material(
      color: drift.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => widget.onGoToStep(step),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 140,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: drift.borderSubtle),
          ),
          child: Column(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: DriftProTheme.labelSm.copyWith(color: drift.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: drift.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: drift.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 12),
          Text(
            value,
            style: DriftProTheme.headingLg.copyWith(color: drift.textPrimary),
          ),
          Text(label, style: DriftProTheme.bodySm.copyWith(color: drift.textMuted)),
        ],
      ),
    );
  }
}
