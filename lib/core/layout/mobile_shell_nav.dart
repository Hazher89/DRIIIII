import 'package:flutter/material.dart';

import '../config/driftpro_client.dart';

/// Bunnmeny som skalerer til mobil — horisontal scroll når mange faner.
class MobileShellNavBar extends StatelessWidget {
  const MobileShellNavBar({
    super.key,
    required this.itemCount,
    required this.builder,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index, {required bool compact})
      builder;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = DriftProClient.isMobile ||
        (itemCount > 6 && width < 420);

    final row = Row(
      mainAxisAlignment:
          compact ? MainAxisAlignment.start : MainAxisAlignment.spaceAround,
      children: List.generate(
        itemCount,
        (i) => builder(context, i, compact: compact),
      ),
    );

    if (!compact) return row;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: row,
    );
  }
}

/// Kompakt nav-item for små skjermer (iPhone).
class ShellNavItemMetrics {
  const ShellNavItemMetrics._({
    required this.iconSize,
    required this.labelSize,
    required this.horizontalPadding,
    required this.minWidth,
  });

  final double iconSize;
  final double labelSize;
  final double horizontalPadding;
  final double minWidth;

  factory ShellNavItemMetrics.of(BuildContext context, {required bool compact}) {
    if (!compact) {
      return const ShellNavItemMetrics._(
        iconSize: 24,
        labelSize: 10,
        horizontalPadding: 12,
        minWidth: 56,
      );
    }
    return const ShellNavItemMetrics._(
      iconSize: 22,
      labelSize: 9,
      horizontalPadding: 10,
      minWidth: 52,
    );
  }
}
