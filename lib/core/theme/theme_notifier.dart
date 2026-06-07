import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Enkel state-holder for lys/mørk/system-modus — lagres mellom økter.
class ThemeNotifier extends ChangeNotifier {
  static const _boxName = 'driftpro_settings';
  static const _themeKey = 'theme_mode';

  ThemeMode _themeMode = ThemeMode.light;
  bool _initialized = false;

  ThemeMode get themeMode => _themeMode;

  bool get isInitialized => _initialized;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  bool isDark(BuildContext context) {
    return switch (_themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
  }

  Future<void> load() async {
    try {
      await Hive.initFlutter();
      final box = await Hive.openBox(_boxName);
      final stored = box.get(_themeKey);
      if (stored is String) {
        _themeMode = _parse(stored);
      }
    } catch (_) {
      // Behold standard lys modus.
    }
    _initialized = true;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    _persist(mode);
  }

  void toggleTheme() {
    setThemeMode(isDarkMode ? ThemeMode.light : ThemeMode.dark);
  }

  Future<void> _persist(ThemeMode mode) async {
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(_themeKey, _serialize(mode));
    } catch (_) {}
  }

  static ThemeMode _parse(String raw) => switch (raw) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };

  static String _serialize(ThemeMode mode) => switch (mode) {
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
        ThemeMode.light => 'light',
      };
}
