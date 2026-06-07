import 'package:flutter/material.dart';

import 'driftpro_colors.dart';

extension DriftProThemeContext on BuildContext {
  DriftProColors get driftColors =>
      Theme.of(this).extension<DriftProColors>() ?? DriftProColors.light;

  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  ColorScheme get colors => Theme.of(this).colorScheme;

  TextTheme get textTheme => Theme.of(this).textTheme;
}
