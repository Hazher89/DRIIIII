import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class DepartmentOverviewStats {
  final int departmentCount;
  final int totalMembers;
  final int withoutLeader;
  final int unassignedEmployees;
  final int awayToday;
  final int onVacationToday;
  final int pendingAbsence;
  final int presentPercent;

  const DepartmentOverviewStats({
    required this.departmentCount,
    required this.totalMembers,
    required this.withoutLeader,
    required this.unassignedEmployees,
    this.awayToday = 0,
    this.onVacationToday = 0,
    this.pendingAbsence = 0,
    this.presentPercent = 100,
  });
}

class DepartmentOverviewHeader extends StatelessWidget {
  final DepartmentOverviewStats stats;
  final VoidCallback? onOrgChart;

  const DepartmentOverviewHeader({
    super.key,
    required this.stats,
    this.onOrgChart,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isDark ? DriftProTheme.darkGradient : DriftProTheme.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: DriftProTheme.cardShadow,
      ),
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
                      'Avdelingsoversikt',
                      style: DriftProTheme.headingMd.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Struktur, ledere, bemanning og live fravær per avdeling.',
                      style: DriftProTheme.bodySm.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (onOrgChart != null)
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                  ),
                  tooltip: 'Organisasjonskart',
                  onPressed: onOrgChart,
                  icon: const Icon(Icons.account_tree_rounded),
                ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _kpi(w, Icons.apartment_rounded, '${stats.departmentCount}', 'Avdelinger'),
                  _kpi(w, Icons.people_alt_rounded, '${stats.totalMembers}', 'Ansatte totalt'),
                  _kpi(
                    w,
                    Icons.person_off_outlined,
                    '${stats.withoutLeader}',
                    'Uten leder',
                    highlight: stats.withoutLeader > 0,
                  ),
                  _kpi(
                    w,
                    Icons.person_add_disabled_outlined,
                    '${stats.unassignedEmployees}',
                    'Uten avdeling',
                    highlight: stats.unassignedEmployees > 0,
                  ),
                  _kpi(
                    w,
                    Icons.event_busy_rounded,
                    '${stats.awayToday}',
                    'Borte i dag',
                    highlight: stats.awayToday > 0,
                  ),
                  _kpi(
                    w,
                    Icons.beach_access_outlined,
                    '${stats.onVacationToday}',
                    'På ferie i dag',
                  ),
                  _kpi(
                    w,
                    Icons.pending_actions_outlined,
                    '${stats.pendingAbsence}',
                    'Venter godkjenning',
                    highlight: stats.pendingAbsence > 0,
                  ),
                  _kpi(
                    w,
                    Icons.groups_outlined,
                    '${stats.presentPercent}%',
                    'Tilstedeværelse i dag',
                    highlight: stats.presentPercent < 80,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _kpi(double width, IconData icon, String value, String label, {bool highlight = false}) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: highlight ? 0.22 : 0.14),
          borderRadius: BorderRadius.circular(14),
          border: highlight
              ? Border.all(color: Colors.white.withValues(alpha: 0.45))
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
