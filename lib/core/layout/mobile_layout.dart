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

  /// Plass under innhold når skjermen har shell-bunnmeny (dock håndterer safe area).
  static double shellBottomInset(BuildContext context) {
    if (!DriftProClient.isMobile) return 0;
    return 12;
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

  /// FAB med liten avstand over shell-dock (dock håndterer allerede safe area).
  static Widget? wrapFab(BuildContext context, Widget? fab) {
    if (fab == null) return null;
    if (!DriftProClient.isMobile) return fab;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
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

/// Bunnfelt rett over shell-dock — ingen ekstra safe-area-gap.
class DockInputBar extends StatelessWidget {
  const DockInputBar({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 8),
    this.border,
  });

  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        border: border,
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
