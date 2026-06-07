import 'package:flutter/material.dart';

/// Refinert fraværspalett — indigo/slate i stedet for trafikklys-farger.
abstract final class AbsencePalette {
  static const Color indigo = Color(0xFF6366F1);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color sky = Color(0xFF0EA5E9);
  static const Color rose = Color(0xFFEC4899);
  static const Color slate = Color(0xFF64748B);
  static const Color slateDark = Color(0xFF334155);
  static const Color slateLight = Color(0xFF94A3B8);

  static const Color attendance = indigo;
  static const Color chartPrimary = indigo;
  static const Color chartSecondary = violet;

  static const Color usageWarning = indigo;
  static const Color usageCritical = Color(0xFF7C3AED);

  /// Nøytral panelbakgrunn — unngår grønn/rød accent-glød.
  static Color panelBackground(bool isDark) =>
      isDark ? const Color(0xFF1E293B).withValues(alpha: 0.35) : const Color(0xFFF8FAFC);

  static Color panelBorder(bool isDark) =>
      isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0);

  /// Tilstedeværelse — én rolig accent, ikke trafikklys.
  static Color attendanceFill(int percent, {Color? accent}) {
    final base = accent ?? attendance;
    if (percent >= 80) return base;
    if (percent >= 50) return Color.lerp(base, slateLight, 0.35)!;
    return Color.lerp(base, slate, 0.25)!;
  }

  static Color attendanceBadge(int percent, {Color? accent}) =>
      attendanceFill(percent, accent: accent);

  /// Rangering — subtile metalltoner, ikke gull/bronse/oransje.
  static Color rankColor(int rank, bool isDark) => switch (rank) {
        1 => indigo,
        2 => slateLight,
        3 => const Color(0xFFCBD5E1),
        _ => isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
      };

  /// Leaderboard-stolpe — indigo med variert metning etter rang.
  static Color leaderboardBar(int rank) => switch (rank) {
        1 => indigo,
        2 => Color.lerp(indigo, violet, 0.35)!,
        3 => Color.lerp(indigo, sky, 0.45)!,
        _ => slateLight,
      };
}
