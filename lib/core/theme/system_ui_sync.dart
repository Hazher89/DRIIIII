import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/driftpro_client.dart';
import 'driftpro_colors.dart';

/// Lys statuslinje-stil: mørke ikoner (klokke/Wi‑Fi/batteri) på lys bakgrunn.
///
/// På iOS styrer [statusBarBrightness]:
/// - [Brightness.light] → mørke ikoner (for lys bakgrunn)
/// - [Brightness.dark] → hvite ikoner (for mørk bakgrunn)
const SystemUiOverlayStyle kDriftProLightSystemUi = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: Colors.white,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarDividerColor: Color(0xFFE0E0E0),
);

/// Holder status-/navigasjonslinje i sync med aktivt tema.
///
/// Må ligge *innenfor* [MaterialApp] (f.eks. via `builder`), ellers mangler
/// tema-kontekst og iOS kan ende med hvite statusikoner på lys bakgrunn.
class SystemUiSync extends StatelessWidget {
  const SystemUiSync({super.key, required this.child});

  final Widget child;

  static void applyLight() {
    if (DriftProClient.isDesktop) return;
    SystemChrome.setSystemUIOverlayStyle(kDriftProLightSystemUi);
  }

  @override
  Widget build(BuildContext context) {
    if (DriftProClient.isDesktop) return child;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final drift = Theme.of(context).extension<DriftProColors>();

    final style = isDark
        ? SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: drift?.navBar ?? const Color(0xFF0E1410),
            systemNavigationBarIconBrightness: Brightness.light,
            systemNavigationBarDividerColor:
                drift?.borderSubtle ?? const Color(0xFF2A3D32),
          )
        : kDriftProLightSystemUi.copyWith(
            systemNavigationBarColor: drift?.navBar ?? Colors.white,
            systemNavigationBarDividerColor:
                drift?.borderSubtle ?? const Color(0xFFE0E0E0),
          );

    SystemChrome.setSystemUIOverlayStyle(style);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style,
      child: child,
    );
  }
}
