import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../config/driftpro_client.dart';

/// Web/desktop-først layout og scroll — unngår mobil «swipe mellom faner».
abstract final class WebLayout {
  /// Pointer-drevet flate (nettleser eller installert desktop).
  static bool get prefersPointerNav =>
      DriftProClient.isWeb || DriftProClient.isDesktop;

  /// Bred arbeidsflate (typisk laptop/desktop i nettleser).
  static bool isWide(BuildContext context, {double minWidth = 960}) =>
      MediaQuery.sizeOf(context).width >= minWidth;

  static bool isDesktopWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1100;

  /// Bakgrunn som føles som web-admin (ikke mobil-app).
  static Color canvasColor(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? const Color(0xFF0F1115) : const Color(0xFFF5F5F7);
  }

  /// Innholdsbredde for lesbarhet på store skjermer.
  static double contentMaxWidth({double wide = 1120}) => wide;

  static EdgeInsets pagePadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1200) return const EdgeInsets.fromLTRB(28, 16, 28, 28);
    if (w >= 800) return const EdgeInsets.fromLTRB(20, 12, 20, 24);
    return const EdgeInsets.fromLTRB(12, 8, 12, 20);
  }

  /// På web/desktop: klikk bytter fane — ingen horisontal swipe.
  static ScrollPhysics tabViewPhysics([ScrollPhysics? override]) {
    if (override != null) return override;
    if (prefersPointerNav) return const NeverScrollableScrollPhysics();
    return const PageScrollPhysics();
  }
}

/// Scroll-oppførsel for web: hjul/trackpad scroller, musetrekk glir ikke sider.
class DriftProScrollBehavior extends MaterialScrollBehavior {
  const DriftProScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices {
    if (kIsWeb || DriftProClient.isDesktop) {
      // Touch/stylus beholdes (nettbrett). Mus skal ikke «dra» sider sidelengs.
      return {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
      };
    }
    return {
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
      PointerDeviceKind.mouse,
      PointerDeviceKind.trackpad,
      PointerDeviceKind.unknown,
    };
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (kIsWeb || DriftProClient.isDesktop) return child;
    return super.buildOverscrollIndicator(context, child, details);
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    if (kIsWeb || DriftProClient.isDesktop) {
      return const ClampingScrollPhysics();
    }
    return super.getScrollPhysics(context);
  }
}

/// [TabBarView] som ikke kan sveipes på web/desktop.
class DriftProTabView extends StatelessWidget {
  const DriftProTabView({
    super.key,
    required this.children,
    this.controller,
    this.physics,
  });

  final TabController? controller;
  final List<Widget> children;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      controller: controller,
      physics: WebLayout.tabViewPhysics(physics),
      children: children,
    );
  }
}

/// Sentralisert innholdskolonne for web-sider.
class WebPageBody extends StatelessWidget {
  const WebPageBody({
    super.key,
    required this.child,
    this.maxWidth = 1120,
    this.padding,
    this.align = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final Alignment align;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ?? WebLayout.pagePadding(context),
          child: child,
        ),
      ),
    );
  }
}
