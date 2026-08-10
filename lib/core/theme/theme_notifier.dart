import 'package:flutter/material.dart';

/// DriftPro bruker kun lys modus (ingen bruker-valg for mørk/system).
class ThemeNotifier extends ChangeNotifier {
  ThemeMode get themeMode => ThemeMode.light;

  bool get isInitialized => true;

  bool get isDarkMode => false;

  bool isDark(BuildContext context) => false;

  Future<void> load() async {}

  void setThemeMode(ThemeMode mode) {
    // Bevisst no-op — Utseende-valg er fjernet.
  }

  void toggleTheme() {
    // Bevisst no-op.
  }
}
