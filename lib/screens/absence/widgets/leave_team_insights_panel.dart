import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/services/absence/leave_team_insights_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';
class LeaveTeamInsightsPanel extends StatelessWidget {
  final TeamLeaveInsightsSnapshot snapshot;
  final CompanyLeaveSettings companySettings;
  final Color Function(AbsenceType) colorForType;

  const LeaveTeamInsightsPanel({
    super.key,
    required this.snapshot,
    required this.companySettings,
    required this.colorForType,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topEgen = snapshot.topEgenmeldingUsers;
    final exhausted =
        snapshot.egenmeldingExhausted(companySettings.effectiveEgenmeldingDaysPerYear);
    final typeEntries = snapshot.daysByTypeYtd.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(isDark),
        const SizedBox(height: 12),
        _kpiRow(isDark),
        const SizedBox(height: 16),
        if (topEgen.isNotEmpty) ...[
          Text('Egenmelding per ansatt', style: DriftProTheme.headingSm),
          const SizedBox(height: 8),
          _egenmeldingBarChart(isDark, topEgen),
          const SizedBox(height: 16),
        ],
        if (typeEntries.isNotEmpty) ...[
          Text('Fravær ${snapshot.year} (godkjente dager)', style: DriftProTheme.headingSm),
          const SizedBox(height: 8),
          _typePieChart(isDark, typeEntries),
          const SizedBox(height: 16),
        ],
        if (exhausted.isNotEmpty) _exhaustedCard(isDark, exhausted),
        const SizedBox(height: 12),
        _employeeTable(isDark),
        const SizedBox(height: 20),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          initiallyExpanded: false,
          title: Row(
            children: [
              Icon(Icons.gavel_rounded, size: 20, color: DriftProTheme.primaryGreen),
              const SizedBox(width: 8),
              Text('Lov og regler (Lovdata)', style: DriftProTheme.headingSm),
            ],
          ),
          children: [
            const SizedBox(height: 8),
            ...LeaveRules.managerOverviewCards().map(
              (c) => _CompactRuleTile(card: c, isDark: isDark),
            ),
          ],
        ),
      ],
    );
  }

  Widget _header(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: DriftProTheme.primaryGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.insights_rounded, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Teamoversikt ${snapshot.year}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  snapshot.scopeLabel,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          if (snapshot.companyWide)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Alle ansatte',
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kpiRow(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _kpi(
            isDark,
            '${snapshot.employees.length}',
            'Ansatte',
            Icons.groups_rounded,
            DriftProTheme.primaryGreen,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kpi(
            isDark,
            '${snapshot.onVacationToday}',
            'På ferie i dag',
            Icons.beach_access_rounded,
            DriftProTheme.absenceVacation,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kpi(
            isDark,
            '${snapshot.egenmeldingExhaustedCount}',
            'Uten egenmelding',
            Icons.warning_amber_rounded,
            DriftProTheme.warning,
          ),
        ),
      ],
    );
  }

  Widget _kpi(bool isDark, String value, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value, style: DriftProTheme.headingSm.copyWith(color: color)),
          Text(
            label,
            textAlign: TextAlign.center,
            style: DriftProTheme.caption,
          ),
        ],
      ),
    );
  }

  Widget _egenmeldingBarChart(bool isDark, List<EmployeeLeaveInsight> rows) {
    final maxCap = companySettings.effectiveEgenmeldingDaysPerYear;
    final maxY = rows
        .map((e) => e.egenmeldingUsed)
        .fold<int>(0, (a, b) => a > b ? a : b)
        .clamp(1, maxCap)
        .toDouble();

    return Container(
      height: 200,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY + 2,
          barTouchData: BarTouchData(enabled: true),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= rows.length) return const SizedBox.shrink();
                  final name = rows[i].profile.fullName.split(' ').first;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      name.length > 6 ? '${name.substring(0, 6)}…' : name,
                      style: const TextStyle(fontSize: 9),
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 4,
          ),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < rows.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: rows[i].egenmeldingUsed.toDouble(),
                    color: rows[i].egenmeldingExhaustedFor(
                            companySettings.effectiveEgenmeldingDaysPerYear)
                        ? DriftProTheme.error
                        : DriftProTheme.absenceSickSelf,
                    width: 16,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _typePieChart(bool isDark, List<MapEntry<AbsenceType, int>> entries) {
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    if (total <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200),
      ),
      child: SizedBox(
        height: 180,
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 32,
                  sections: entries.map((e) {
                    final pct = (e.value / total * 100).toStringAsFixed(0);
                    return PieChartSectionData(
                      value: e.value.toDouble(),
                      color: colorForType(e.key),
                      title: '$pct%',
                      radius: 48,
                      titleStyle: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colorForType(e.key),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${e.key.label} (${e.value})',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _exhaustedCard(bool isDark, List<EmployeeLeaveInsight> list) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DriftProTheme.error.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DriftProTheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: DriftProTheme.error, size: 20),
              const SizedBox(width: 8),
              Text(
                'Ingen egenmelding igjen (${list.length})',
                style: DriftProTheme.labelLg.copyWith(color: DriftProTheme.error),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...list.take(6).map(
            (e) => Text(
              '• ${e.profile.fullName} — ${e.egenmeldingUsed}/${companySettings.effectiveEgenmeldingDaysPerYear} dager, '
              '${e.egenmeldingPeriodsUsed}/${LeaveRules.egenmeldingMaxPeriodsPerYear} perioder',
              style: DriftProTheme.bodySm,
            ),
          ),
          if (list.length > 6)
            Text('+ ${list.length - 6} til', style: DriftProTheme.caption),
        ],
      ),
    );
  }

  Widget _employeeTable(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Text('Alle ansatte', style: DriftProTheme.headingSm),
                const Spacer(),
                Text(
                  'Egenm. / Ferie igjen',
                  style: DriftProTheme.caption,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...snapshot.employees.map((e) {
            final egenColor = e.egenmeldingExhaustedFor(
                    companySettings.effectiveEgenmeldingDaysPerYear)
                ? DriftProTheme.error
                : e.egenmeldingUsed >= companySettings.effectiveEgenmeldingDaysPerYear - 3
                    ? DriftProTheme.warning
                    : DriftProTheme.primaryGreen;
            return ListTile(
              dense: true,
              title: Text(e.profile.fullName, style: DriftProTheme.bodyMd),
              subtitle: Text(
                '${e.absencesYtdDays} fraværsdager i ${snapshot.year}',
                style: DriftProTheme.caption,
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${e.egenmeldingRemaining} egenm.',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: egenColor,
                    ),
                  ),
                  Text(
                    '${e.vacationRemaining} ferie',
                    style: DriftProTheme.caption,
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _CompactRuleTile extends StatelessWidget {
  final LeaveRuleCard card;
  final bool isDark;

  const _CompactRuleTile({required this.card, required this.isDark});

  IconData get _icon {
    switch (card.iconName) {
      case 'child':
        return Icons.child_care_rounded;
      case 'sun':
        return Icons.wb_sunny_rounded;
      case 'medical':
        return Icons.medical_services_outlined;
      case 'timer':
        return Icons.timer_outlined;
      case 'shield':
        return Icons.health_and_safety_outlined;
      case 'lock':
        return Icons.lock_outline_rounded;
      case 'tips':
        return Icons.lightbulb_outline_rounded;
      default:
        return Icons.person_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, size: 18, color: DriftProTheme.primaryGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.title, style: DriftProTheme.labelLg),
                const SizedBox(height: 4),
                Text(card.body, style: DriftProTheme.bodySm.copyWith(height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
