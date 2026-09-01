import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Mørk/lys chat-tema (rom-lokalt).
abstract final class ChatTheme {
  static bool dark = false;

  static Color surface(BuildContext context) => dark ? const Color(0xFF152019) : Colors.white;

  static Color bubbleOther(BuildContext context) => dark ? const Color(0xFF1E2A24) : Colors.white;

  static Color textPrimary(BuildContext context) => dark ? Colors.white : const Color(0xFF1A1A1A);

  static Color inputFill(BuildContext context) =>
      dark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF3F5F4);

  static LinearGradient backgroundGradient(BuildContext context) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: dark
            ? [const Color(0xFF0B1410), const Color(0xFF101810), const Color(0xFF0D1A12)]
            : [const Color(0xFFF4F7F5), Colors.white, DriftProTheme.primaryGreen.withValues(alpha: 0.03)],
      );
}
