import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/time_clock/time_overtime_summary.dart';

/// Viser overtid etter arbeidsmiljøloven §10-4 og §10-6.
class TimeClockOvertimePanel extends StatelessWidget {
  const TimeClockOvertimePanel({
    super.key,
    required this.summary,
  });

  final TimeOvertimeSummary summary;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final legal = summary.legal;

    if (summary.exempt) {
      return _card(
        isDark,
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.grey.shade600),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Ansatt er unntatt arbeidstidskapitlet (f.eks. lederstilling, §10-12). '
                'Overtidsregler gjelder ikke.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.gavel_outlined, size: 20, color: DriftProTheme.primaryGreen),
                  const SizedBox(width: 8),
                  const Text(
                    'Overtid — arbeidsmiljøloven',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '§10-4: Maks ${legal.dailyLimitHours.toStringAsFixed(0)} t/døgn og '
                '${legal.weeklyLimitHours.toStringAsFixed(0)} t/uke alminnelig arbeidstid. '
                '§10-6 (11): Minst ${legal.overtimeSupplementPct.toStringAsFixed(0)} % tillegg på overtidsarbeid.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth > 520;
                  final stats = [
                    _statTile(
                      'Arbeidstid uke',
                      '${summary.weekShiftHours.toStringAsFixed(1)} t',
                      subtitle: 'Grense ${legal.weeklyLimitHours.toStringAsFixed(0)} t',
                      highlight: summary.weekShiftHours > legal.weeklyLimitHours,
                    ),
                    _statTile(
                      'Overtid uke',
                      '${summary.weekOvertimeHours.toStringAsFixed(1)} t',
                      subtitle: 'Maks ${summary.limits.weeklyMax.toStringAsFixed(0)} t',
                      highlight: summary.limits.weeklyExceeded,
                      color: const Color(0xFFDC2626),
                    ),
                    _statTile(
                      '40 % tillegg',
                      '${summary.weekSupplementHours.toStringAsFixed(2)} t',
                      subtitle: 'Utbetales i penger',
                      color: const Color(0xFFB45309),
                    ),
                  ];
                  if (wide) {
                    return Row(
                      children: stats
                          .map((s) => Expanded(child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: s,
                              )))
                          .toList(),
                    );
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: stats
                        .map((s) => SizedBox(width: (c.maxWidth - 8) / 2, child: s))
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _limitsCard(isDark),
        if (summary.hasOvertime) ...[
          const SizedBox(height: 12),
          _dailyCard(isDark),
        ],
      ],
    );
  }

  Widget _limitsCard(bool isDark) {
    final limits = summary.limits;
    final regime = summary.legal.regimeLabel;

    return _card(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Overtidsgrenser — $regime', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _limitRow(
            'Denne uken',
            limits.weeklyOvertime,
            limits.weeklyMax,
            limits.weeklyExceeded,
          ),
          const SizedBox(height: 8),
          _limitRow(
            'Siste 4 uker',
            limits.fourWeekOvertime,
            limits.fourWeekMax,
            limits.fourWeekExceeded,
          ),
          const SizedBox(height: 8),
          _limitRow(
            'Siste 52 uker',
            limits.annualOvertime,
            limits.annualMax,
            limits.annualExceeded,
          ),
          if (summary.hasLimitWarning) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: DriftProTheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DriftProTheme.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: DriftProTheme.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Overtidsgrense overskredet. Sjekk §10-6 og dokumenter årsak.',
                      style: TextStyle(fontSize: 12, color: DriftProTheme.error.withValues(alpha: 0.9)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dailyCard(bool isDark) {
    final daysWithOt = summary.daily.where((d) => d.overtimeHours > 0).toList();
    if (daysWithOt.isEmpty) return const SizedBox.shrink();

    return _card(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Overtid per dag', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ...daysWithOt.map((d) {
            final label = DateFormat('EEEE d. MMM', 'nb').format(d.date);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
                  Text(
                    '${d.shiftHours.toStringAsFixed(1)} t',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '+${d.overtimeHours.toStringAsFixed(1)} t OT',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _limitRow(String label, double value, double max, bool exceeded) {
    final pct = max > 0 ? (value / max).clamp(0.0, 1.2) : 0.0;
    final color = exceeded ? DriftProTheme.error : DriftProTheme.primaryGreen;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            Text(
              '${value.toStringAsFixed(1)} / ${max.toStringAsFixed(0)} t',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: exceeded ? DriftProTheme.error : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct > 1 ? 1 : pct,
            minHeight: 6,
            backgroundColor: Colors.grey.shade200,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _statTile(
    String label,
    String value, {
    String? subtitle,
    bool highlight = false,
    Color? color,
  }) {
    final accent = color ?? (highlight ? DriftProTheme.error : DriftProTheme.primaryGreen);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: accent),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ],
      ),
    );
  }

  Widget _card(bool isDark, {required Widget child}) {
    return Card(
      elevation: 0,
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }
}
