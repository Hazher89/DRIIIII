import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/driftpro_client.dart';
import 'driftpro_theme_context.dart';

/// Holder status-/navigasjonslinje i sync med aktivt tema.
class SystemUiSync extends StatelessWidget {
  const SystemUiSync({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final drift = context.driftColors;

    if (!DriftProClient.isDesktop) {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: drift.navBar,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarDividerColor: drift.borderSubtle,
        ),
      );
    }

    return child;
  }
}
