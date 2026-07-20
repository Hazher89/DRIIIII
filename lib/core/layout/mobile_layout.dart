import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/driftpro_client.dart';

/// Felles layout for iOS/Android — dialogbredde, FAB-inset, scroll-padding.
abstract final class MobileLayout {
  /// Kun native iOS/Android — endrer ikke web/desktop.
  static bool get isNativeMobile => DriftProClient.isMobile;

  /// Smal skjerm eller native mobil.
  static bool isCompact(BuildContext context) {
    return DriftProClient.isMobile ||
        MediaQuery.sizeOf(context).width < 600;
  }

  /// Plass under innhold når skjermen har shell-bunnmeny + FAB.
  static double shellBottomInset(BuildContext context) {
    if (!DriftProClient.isMobile) return 0;
    return 12 + MediaQuery.paddingOf(context).bottom;
  }

  /// Ekstra padding nederst i scroll-lister (FAB + bunnmeny).
  static EdgeInsets listBottomPadding(
    BuildContext context, {
    double extra = 24,
    bool withFab = false,
  }) {
    final fab = withFab && DriftProClient.isMobile ? 72.0 : 0.0;
    return EdgeInsets.only(
      bottom: extra + fab + shellBottomInset(context),
    );
  }

  /// Dialogbredde som aldri overflower iPhone.
  static double dialogWidth(BuildContext context, {double max = 460}) {
    final w = MediaQuery.sizeOf(context).width;
    return math.min(max, w - 32);
  }

  /// Begrens dialog-innhold til skjermbredde.
  static BoxConstraints dialogConstraints(
    BuildContext context, {
    double maxWidth = 460,
    double maxHeightFraction = 0.88,
  }) {
    final size = MediaQuery.sizeOf(context);
    return BoxConstraints(
      maxWidth: dialogWidth(context, max: maxWidth),
      maxHeight: size.height * maxHeightFraction,
    );
  }

  /// FAB med avstand fra bunn på mobil.
  static Widget? wrapFab(BuildContext context, Widget? fab) {
    if (fab == null) return null;
    if (!DriftProClient.isMobile) return fab;
    return Padding(
      padding: EdgeInsets.only(bottom: shellBottomInset(context)),
      child: fab,
    );
  }

  static FloatingActionButtonLocation get fabLocation =>
      FloatingActionButtonLocation.endFloat;

  /// Responsiv innlogging / kortbredde.
  static double cardWidth(BuildContext context, {double max = 450}) {
    final w = MediaQuery.sizeOf(context).width;
    return math.min(max, w - 32);
  }

  static EdgeInsets cardPadding(BuildContext context) {
    return EdgeInsets.all(isCompact(context) ? 24 : 40);
  }
}

/// Dialog-innhold med riktig bredde på iPhone.
class MobileDialogBody extends StatelessWidget {
  const MobileDialogBody({
    super.key,
    required this.child,
    this.maxWidth = 460,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: MobileLayout.dialogConstraints(
        context,
        maxWidth: maxWidth,
      ),
      child: child,
    );
  }
}

/// SafeArea nederst for lagre-knapper i skjema.
class MobileBottomActionBar extends StatelessWidget {
  const MobileBottomActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: child,
      ),
    );
  }
}
