import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum LeaveUsageLevel { ok, warning, critical }

/// Felles fargekoding: grønn/base → oransje (nær max) → rød (max nådd).
abstract final class LeaveUsageColors {
  static const double warningRatio = 0.75;

  static LeaveUsageLevel levelFromUsed(int used, int max) {
    if (max <= 0) return LeaveUsageLevel.ok;
    if (used >= max) return LeaveUsageLevel.critical;
    if (used / max >= warningRatio) return LeaveUsageLevel.warning;
    return LeaveUsageLevel.ok;
  }

  static LeaveUsageLevel levelFromRemaining(int remaining, int total) {
    if (total <= 0) return LeaveUsageLevel.ok;
    if (remaining <= 0) return LeaveUsageLevel.critical;
    if (remaining / total <= 1 - warningRatio) return LeaveUsageLevel.warning;
    return LeaveUsageLevel.ok;
  }

  static LeaveUsageLevel worst(LeaveUsageLevel a, LeaveUsageLevel b) {
    if (a == LeaveUsageLevel.critical || b == LeaveUsageLevel.critical) {
      return LeaveUsageLevel.critical;
    }
    if (a == LeaveUsageLevel.warning || b == LeaveUsageLevel.warning) {
      return LeaveUsageLevel.warning;
    }
    return LeaveUsageLevel.ok;
  }

  static Color colorFor(LeaveUsageLevel level, Color base) {
    return switch (level) {
      LeaveUsageLevel.ok => base,
      LeaveUsageLevel.warning => Colors.orange.shade700,
      LeaveUsageLevel.critical => DriftProTheme.error,
    };
  }
}
