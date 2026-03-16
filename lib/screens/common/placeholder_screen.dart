import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class PlaceholderScreen extends StatelessWidget {
  final String title;
  final String description;

  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            description,
            style: DriftProTheme.bodyLg.copyWith(
              color: isDark ? Colors.grey[200] : Colors.grey[800],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

