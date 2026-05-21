import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/user_profile.dart';

/// Visningshjelp for ansattlister — ansattnummer brukes ved innlogging.
class EmployeeDisplay {
  EmployeeDisplay._();

  static String? employeeNumberLabel(UserProfile user) {
    final n = user.employeeNumber?.trim();
    if (n == null || n.isEmpty) return null;
    return 'Ansattnr. $n';
  }

  static Widget nameWithNumber(
    UserProfile user, {
    TextStyle? nameStyle,
    bool emphasizeNumber = true,
  }) {
    final no = employeeNumberLabel(user);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          user.fullName,
          style: nameStyle ?? const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        if (no != null) ...[
          const SizedBox(height: 2),
          Text(
            no,
            style: TextStyle(
              fontSize: emphasizeNumber ? 13 : 12,
              fontWeight: emphasizeNumber ? FontWeight.w700 : FontWeight.w500,
              color: emphasizeNumber ? DriftProTheme.primaryGreen : null,
            ),
          ),
        ],
      ],
    );
  }
}
