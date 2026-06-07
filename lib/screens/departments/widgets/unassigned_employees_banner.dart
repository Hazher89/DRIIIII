import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/user_profile.dart';
import '../../employees/widgets/employee_display.dart';

class UnassignedEmployeesBanner extends StatelessWidget {
  final List<UserProfile> employees;
  final bool initiallyExpanded;

  const UnassignedEmployeesBanner({
    super.key,
    required this.employees,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    if (employees.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? DriftProTheme.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DriftProTheme.warning.withValues(alpha: 0.35)),
          boxShadow: DriftProTheme.cardShadow,
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: DriftProTheme.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.person_search_rounded, color: DriftProTheme.warning),
            ),
            title: Text(
              '${employees.length} ansatte uten avdeling',
              style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Disse bør knyttes til en avdeling for riktig tilgang og oversikt.',
              style: DriftProTheme.caption,
            ),
            children: employees
                .take(12)
                .map(
                  (p) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                      child: Text(
                        p.initials,
                        style: const TextStyle(
                          fontSize: 11,
                          color: DriftProTheme.primaryGreen,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    title: EmployeeDisplay.nameWithNumber(p),
                    subtitle: Text(p.jobTitle ?? p.role.name),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}
