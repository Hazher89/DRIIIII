import 'package:flutter/material.dart';

import '../../absence/widgets/leave_absence_rate_widgets.dart';
import '../../../core/theme/absence_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/department.dart';
import '../../../models/user_profile.dart';
import 'department_absence_panel.dart';
import 'department_absence_stats.dart';
import 'department_ui_helpers.dart';

class DepartmentGridCard extends StatelessWidget {
  final Department department;
  final List<UserProfile> members;
  final List<UserProfile> leaders;
  final DepartmentAbsenceOverview absenceStats;
  final VoidCallback onTap;

  const DepartmentGridCard({
    super.key,
    required this.department,
    required this.members,
    required this.leaders,
    required this.absenceStats,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = DepartmentUiHelpers.parseColor(department.colorCode);
    final needsLeader = leaders.isEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: isDark ? DriftProTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
            ),
            boxShadow: DriftProTheme.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            DepartmentUiHelpers.iconForName(department.iconName),
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                department.name,
                                style: DriftProTheme.headingSm.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (department.description != null &&
                                  department.description!.trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  department.description!.trim(),
                                  style: DriftProTheme.bodySm.copyWith(
                                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_outward_rounded,
                          size: 18,
                          color: isDark ? Colors.grey[500] : Colors.grey[400],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _memberAvatars(members, color),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${members.length} ansatt${members.length == 1 ? '' : 'e'}',
                            style: DriftProTheme.labelMd,
                          ),
                        ),
                        if (absenceStats.memberCount > 0 && absenceStats.totalDaysYtd > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: AbsenceRateBadge(
                              percent: absenceStats.averageAbsencePercent,
                              compact: true,
                            ),
                          ),
                        if (needsLeader)
                          _badge('Mangler leder', AbsencePalette.indigo.withValues(alpha: 0.12),
                              textColor: AbsencePalette.indigo)
                        else
                          _badge('OK', color.withValues(alpha: 0.12), textColor: color),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DepartmentAbsencePanel(stats: absenceStats, accent: color),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            needsLeader ? Icons.warning_amber_rounded : Icons.verified_user_outlined,
                            size: 16,
                            color: needsLeader ? AbsencePalette.indigo : color,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              needsLeader
                                  ? 'Tildel leder i avdelingen'
                                  : 'Leder: ${DepartmentUiHelpers.leaderLabel(leaders)}',
                              style: DriftProTheme.caption.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.grey[300] : Colors.grey[800],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _memberAvatars(List<UserProfile> members, Color color) {
    final preview = members.take(4).toList();
    if (preview.isEmpty) {
      return CircleAvatar(
        radius: 14,
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(Icons.person_outline, size: 16, color: color),
      );
    }
    return SizedBox(
      width: preview.length > 1 ? 14.0 + (preview.length - 1) * 18.0 + 14.0 : 28,
      height: 28,
      child: Stack(
        children: [
          for (var i = 0; i < preview.length; i++)
            Positioned(
              left: i * 18.0,
              child: CircleAvatar(
                radius: 14,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Text(
                  preview[i].initials,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color bg, {Color? textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: textColor ?? DriftProTheme.warning,
        ),
      ),
    );
  }
}
