import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/department.dart';
import '../../../models/user_profile.dart';

class DepartmentUiHelpers {
  DepartmentUiHelpers._();

  static Color parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return DriftProTheme.primaryGreen;
    }
  }

  static IconData iconForName(String name) {
    switch (name) {
      case 'business':
        return AppIcons.business;
      case 'group':
        return Icons.groups_rounded;
      case 'build':
        return Icons.construction_rounded;
      case 'safety':
        return Icons.health_and_safety_rounded;
      case 'local_shipping':
        return Icons.local_shipping_rounded;
      case 'warehouse':
        return Icons.warehouse_rounded;
      default:
        return AppIcons.department;
    }
  }

  static List<UserProfile> membersFor(
    Department dept,
    Map<String, List<UserProfile>> byDept,
  ) =>
      byDept[dept.id] ?? const [];

  static List<UserProfile> leadersFor(
    Department dept,
    Map<String, UserProfile> profileById,
  ) =>
      dept.leaderIds
          .map((id) => profileById[id])
          .whereType<UserProfile>()
          .toList();

  static String leaderLabel(List<UserProfile> leaders) {
    if (leaders.isEmpty) return 'Ingen leder valgt';
    if (leaders.length == 1) return leaders.first.fullName;
    return '${leaders.first.fullName} +${leaders.length - 1}';
  }
}
