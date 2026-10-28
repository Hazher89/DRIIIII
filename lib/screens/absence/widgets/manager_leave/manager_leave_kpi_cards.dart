import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../models/absence.dart';
import 'manager_leave_helpers.dart';

class ManagerLeaveKpiCards extends StatelessWidget {
  const ManagerLeaveKpiCards({
    super.key,
    required this.pendingCount,
    required this.awayToday,
    required this.onJobCount,
    required this.totalEmployees,
    required this.nextWeekAwayCount,
    required this.onScrollToApprovals,
  });

  final int pendingCount;
  final List<Absence> awayToday;
  final int onJobCount;
  final int totalEmployees;
  final int nextWeekAwayCount;
  final VoidCallback onScrollToApprovals;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final capacityPct = totalEmployees == 0
        ? 100
        : (((totalEmployees - nextWeekAwayCount) / totalEmployees) * 100)
            .round()
            .clamp(0, 100);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        final cards = [
          _KpiCard(
            isDark: isDark,
            accent: pendingCount > 0
                ? DriftProTheme.warning
                : DriftProTheme.success,
            icon: Icons.pending_actions_outlined,
            title: 'Venter på godkjenning',
            value: pendingCount > 0
                ? '$pendingCount ${pendingCount == 1 ? 'ny søknad' : 'nye søknader'}'
                : 'Ingen ventende',
            subtitle: pendingCount > 0
                ? 'Trykk for å gå til handlingslisten'
                : 'Alt er behandlet',
            badge: pendingCount > 0 ? '$pendingCount' : null,
            onTap: pendingCount > 0 ? onScrollToApprovals : null,
          ),
          _KpiCard(
            isDark: isDark,
            accent: DriftProTheme.primaryGreen,
            icon: Icons.groups_outlined,
            title: 'Borte i dag',
            value: awayToday.isEmpty
                ? 'Alle på jobb'
                : '${awayToday.length} borte',
            subtitle: '$onJobCount av $totalEmployees på jobb',
            child: awayToday.isEmpty
                ? null
                : Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: awayToday.take(6).map((a) {
                      final status = ManagerLeaveHelpers.todayStatusFor([a]);
                      return _AwayChip(
                        name: a.userName ?? 'Ansatt',
                        color: status.color,
                        label: a.type.label,
                      );
                    }).toList(),
                  ),
          ),
          _KpiCard(
            isDark: isDark,
            accent: DriftProTheme.absenceVacation,
            icon: Icons.event_available_outlined,
            title: 'Planlagt fravær / Bemanning',
            value: nextWeekAwayCount == 0
                ? 'Full kapasitet neste uke'
                : '$nextWeekAwayCount ansatte planlagt fri neste uke',
            subtitle: '$capacityPct% kapasitet',
          ),
        ];

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }

        return Column(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              cards[i],
            ],
          ],
        );
      },
    );
  }
}

class _AwayChip extends StatelessWidget {
  const _AwayChip({
    required this.name,
    required this.color,
    required this.label,
  });

  final String name;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            name.split(' ').first,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.isDark,
    required this.accent,
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    this.badge,
    this.child,
    this.onTap,
  });

  final bool isDark;
  final Color accent;
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final String? badge;
  final Widget? child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? DriftProTheme.dividerDark
              : const Color(0xFFE8EEF0),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: DriftProTheme.labelMd.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Colors.white70
                        : const Color(0xFF475569),
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              else if (onTap != null)
                Icon(Icons.arrow_forward_rounded,
                    size: 18, color: accent.withValues(alpha: 0.7)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: DriftProTheme.headingSm.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 22,
              height: 1.15,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: DriftProTheme.caption.copyWith(
              color: isDark ? Colors.white54 : const Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (child != null) ...[
            const SizedBox(height: 12),
            child!,
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: card,
      ),
    );
  }
}
