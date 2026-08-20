import 'package:flutter/material.dart';

import '../../absence/widgets/leave_absence_rate_widgets.dart';
import '../../../core/theme/absence_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/department.dart';
import '../../../models/user_profile.dart';
import 'department_absence_panel.dart';
import 'department_absence_stats.dart';
import 'department_ui_helpers.dart';

/// Avdelingskort: ekte tall, tydelig status, hurtig redigering.
class DepartmentGridCard extends StatelessWidget {
  final Department department;
  final List<UserProfile> members;
  final List<UserProfile> leaders;
  final DepartmentAbsenceOverview absenceStats;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onMembers;
  final VoidCallback? onLeave;

  const DepartmentGridCard({
    super.key,
    required this.department,
    required this.members,
    required this.leaders,
    required this.absenceStats,
    required this.onOpen,
    this.onEdit,
    this.onMembers,
    this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = DepartmentUiHelpers.parseColor(department.colorCode);
    final needsLeader = leaders.isEmpty;
    final s = absenceStats;
    final border = isDark ? DriftProTheme.dividerDark : const Color(0xFFE2E8F0);
    final surface = isDark ? DriftProTheme.cardDark : Colors.white;

    return Material(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 4, color: color),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      DepartmentUiHelpers.iconForName(department.iconName),
                      color: color,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          department.name,
                          style: DriftProTheme.headingSm.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            height: 1.15,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          needsLeader
                              ? 'Mangler leder — tildel under Ledere'
                              : 'Leder: ${DepartmentUiHelpers.leaderLabel(leaders)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: needsLeader
                                ? AbsencePalette.indigo
                                : (isDark ? Colors.grey[400] : Colors.grey[600]),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(
                    label: needsLeader ? 'Mangler leder' : 'Aktiv',
                    color: needsLeader ? AbsencePalette.indigo : color,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: _KpiTile(
                      label: 'Ansatte',
                      value: '${members.length}',
                      hint: members.isEmpty ? 'Tom' : 'i avdeling',
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _KpiTile(
                      label: 'På jobb',
                      value: s.memberCount == 0 ? '—' : '${s.presentCount}',
                      hint: s.memberCount == 0
                          ? '—'
                          : 'av ${s.memberCount} · ${s.presentPercent}%',
                      color: AbsencePalette.sky,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _KpiTile(
                      label: 'Ventende',
                      value: '${s.pendingCount}',
                      hint: s.upcomingWeek > 0
                          ? '${s.upcomingWeek} neste 7 d'
                          : 'godkjenning',
                      color: s.pendingCount > 0
                          ? DriftProTheme.warning
                          : AbsencePalette.slate,
                      emphasize: s.pendingCount > 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _KpiTile(
                      label: 'Fravær',
                      value: s.memberCount == 0
                          ? '—'
                          : '${s.averageAbsencePercentRounded}%',
                      hint: s.totalDaysYtd > 0
                          ? '${s.totalDaysYtd} d i år'
                          : 'snitt i år',
                      color: AbsencePalette.indigo,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: DepartmentAbsencePanel(stats: s, accent: color),
            ),
            if (members.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Row(
                  children: [
                    _memberAvatars(members, color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _awayLabel(s),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.grey[400] : Colors.grey[700],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (s.averageAbsencePercent > 0)
                      AbsenceRateBadge(
                        percent: s.averageAbsencePercent,
                        compact: true,
                      ),
                  ],
                ),
              ),
            Divider(height: 1, color: border),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              child: Row(
                children: [
                  _ActionBtn(
                    icon: Icons.open_in_new_rounded,
                    label: 'Åpne',
                    onTap: onOpen,
                  ),
                  _ActionBtn(
                    icon: Icons.edit_outlined,
                    label: 'Rediger',
                    onTap: onEdit ?? onOpen,
                  ),
                  _ActionBtn(
                    icon: Icons.groups_outlined,
                    label: 'Ansatte',
                    onTap: onMembers ?? onOpen,
                  ),
                  _ActionBtn(
                    icon: Icons.event_available_outlined,
                    label: 'Fravær',
                    onTap: onLeave ?? onOpen,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _awayLabel(DepartmentAbsenceOverview s) {
    if (s.memberCount == 0) return 'Ingen ansatte';
    if (s.awayToday == 0) return 'Alle på jobb i dag';
    final parts = <String>[];
    if (s.onVacationToday > 0) parts.add('${s.onVacationToday} ferie');
    if (s.otherAbsenceToday > 0) parts.add('${s.otherAbsenceToday} fravær');
    return '${s.awayToday} borte${parts.isEmpty ? '' : ' · ${parts.join(', ')}'}';
  }

  Widget _memberAvatars(List<UserProfile> members, Color color) {
    final preview = members.take(4).toList();
    return SizedBox(
      width: preview.length > 1 ? 14.0 + (preview.length - 1) * 16.0 + 14.0 : 28,
      height: 28,
      child: Stack(
        children: [
          for (var i = 0; i < preview.length; i++)
            Positioned(
              left: i * 16.0,
              child: CircleAvatar(
                radius: 13,
                backgroundColor: color.withValues(alpha: 0.16),
                child: Text(
                  preview[i].initials,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final String hint;
  final Color color;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: emphasize
            ? color.withValues(alpha: 0.12)
            : (isDark
                ? Colors.white.withValues(alpha: 0.04)
                : const Color(0xFFF8FAFC)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: emphasize
              ? color.withValues(alpha: 0.35)
              : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              height: 1.05,
              color: color,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 6),
          visualDensity: VisualDensity.compact,
          foregroundColor: DriftProTheme.primaryGreen,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
