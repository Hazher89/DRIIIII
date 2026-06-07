import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/strategic_goals_2026.dart';
import '../../../core/theme/app_theme.dart';

enum StrategicGoalStatus { onTrack, watch, noData }

class StrategicGoalLiveMetrics {
  final double? absenceRatePercent;
  final int? criticalTickets;
  final int? plannedSafetyRounds;
  final int? openTickets;

  const StrategicGoalLiveMetrics({
    this.absenceRatePercent,
    this.criticalTickets,
    this.plannedSafetyRounds,
    this.openTickets,
  });

  static const empty = StrategicGoalLiveMetrics();
}

class StrategicGoalsOverview extends StatelessWidget {
  final StrategicGoalLiveMetrics live;
  final String? greetingName;
  final DateTime? referenceDate;

  const StrategicGoalsOverview({
    super.key,
    this.live = StrategicGoalLiveMetrics.empty,
    this.greetingName,
    this.referenceDate,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final date = referenceDate ?? DateTime.now();
    final dateLabel = DateFormat('EEEE d. MMMM yyyy', 'nb_NO').format(date);
    final goals = StrategicGoals2026.goals;
    final tracked = goals.where((g) => _liveValue(g) != null).length;
    final onTrack = goals.where((g) => _status(g) == StrategicGoalStatus.onTrack).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heroHeader(isDark, dateLabel, goals.length, tracked, onTrack),
          const SizedBox(height: 16),
          for (final cat in StrategicGoalCategory.values) ...[
            _categorySection(context, cat, isDark),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _heroHeader(
    bool isDark,
    String dateLabel,
    int totalGoals,
    int tracked,
    int onTrack,
  ) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E3A5F), Color(0xFF0D9488)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D9488).withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greetingName != null && greetingName!.isNotEmpty
                          ? 'Hei, $greetingName'
                          : 'Velkommen',
                      style: DriftProTheme.bodyMd.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      StrategicGoals2026.title,
                      style: DriftProTheme.headingLg.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      StrategicGoals2026.subtitle,
                      style: DriftProTheme.bodySm.copyWith(color: Colors.white60),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  children: [
                    Text(
                      '2026',
                      style: DriftProTheme.headingSm.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'MAVI',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.75),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            dateLabel,
            style: DriftProTheme.caption.copyWith(color: Colors.white54),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _heroChip('$totalGoals mål', Icons.flag_outlined),
              _heroChip('$tracked med live data', Icons.insights_outlined),
              _heroChip('$onTrack på sporet', Icons.check_circle_outline),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _categorySection(
    BuildContext context,
    StrategicGoalCategory category,
    bool isDark,
  ) {
    final color = StrategicGoals2026.categoryColor(category);
    final items = StrategicGoals2026.goals
        .where((g) => g.category == category)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              StrategicGoals2026.categoryLabel(category),
              style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Text(
              '${items.length} KPI',
              style: DriftProTheme.caption.copyWith(
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            if (wide) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: constraints.maxWidth >= 1100 ? 4 : 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.55,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) => _goalCard(items[i], color, isDark),
              );
            }
            return Column(
              children: [
                for (final g in items) ...[
                  _goalCard(g, color, isDark),
                  const SizedBox(height: 8),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _goalCard(StrategicGoal goal, Color accent, bool isDark) {
    final status = _status(goal);
    final liveValue = _liveValue(goal);
    final liveLabel = _liveLabel(goal, liveValue);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == StrategicGoalStatus.onTrack
              ? accent.withValues(alpha: 0.35)
              : (isDark ? DriftProTheme.dividerDark : Colors.grey.shade200),
          width: status == StrategicGoalStatus.onTrack ? 1.5 : 1,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(goal.icon, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.title,
                      style: DriftProTheme.labelMd.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      goal.targetDisplay,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
              _statusChip(status),
            ],
          ),
          if (liveLabel != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Nå: ',
                  style: DriftProTheme.caption.copyWith(fontSize: 10),
                ),
                Text(
                  liveLabel,
                  style: DriftProTheme.caption.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ],
            ),
            if (liveValue != null && goal.targetValue != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress(goal, liveValue).clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: accent.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              ),
            ],
          ],
          const Spacer(),
          Text(
            goal.description,
            style: TextStyle(
              fontSize: 10,
              height: 1.35,
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _statusChip(StrategicGoalStatus status) {
    final (label, color) = switch (status) {
      StrategicGoalStatus.onTrack => ('OK', const Color(0xFF059669)),
      StrategicGoalStatus.watch => ('Følg opp', const Color(0xFFD97706)),
      StrategicGoalStatus.noData => ('Mål', const Color(0xFF64748B)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  double? _liveValue(StrategicGoal goal) {
    return switch (goal.metricKey) {
      'absence_rate' => live.absenceRatePercent,
      'critical_tickets' => live.criticalTickets?.toDouble(),
      'safety_rounds_planned' => live.plannedSafetyRounds?.toDouble(),
      _ => null,
    };
  }

  String? _liveLabel(StrategicGoal goal, double? value) {
    if (value == null) return null;
    return switch (goal.metricKey) {
      'absence_rate' => '${value.toStringAsFixed(1)} %',
      'critical_tickets' => '${value.round()} kritiske avvik',
      'safety_rounds_planned' => '${value.round()} planlagt',
      _ => value.toString(),
    };
  }

  double _progress(StrategicGoal goal, double value) {
    final target = goal.targetValue;
    if (target == null || target <= 0) return 0;
    return switch (goal.compare) {
      StrategicGoalCompare.max => (value / target).clamp(0, 1),
      StrategicGoalCompare.min => (value / target).clamp(0, 1),
      StrategicGoalCompare.zeroBest => value <= 0 ? 1 : 0.2,
      StrategicGoalCompare.exact => 0.5,
    };
  }

  StrategicGoalStatus _status(StrategicGoal goal) {
    final value = _liveValue(goal);
    if (value == null) return StrategicGoalStatus.noData;
    final target = goal.targetValue;

    return switch (goal.compare) {
      StrategicGoalCompare.max when target != null =>
        value <= target ? StrategicGoalStatus.onTrack : StrategicGoalStatus.watch,
      StrategicGoalCompare.min when target != null =>
        value >= target ? StrategicGoalStatus.onTrack : StrategicGoalStatus.watch,
      StrategicGoalCompare.zeroBest =>
        value <= 0 ? StrategicGoalStatus.onTrack : StrategicGoalStatus.watch,
      StrategicGoalCompare.exact => StrategicGoalStatus.noData,
      _ => StrategicGoalStatus.noData,
    };
  }
}
