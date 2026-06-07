import 'package:flutter/material.dart';

import '../../core/theme/driftpro_theme_context.dart';

/// Standard DriftPro-kort med tema-støtte.
class DriftProSurface extends StatelessWidget {
  const DriftProSurface({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.elevated = false,
    this.radius = 16,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool elevated;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final decoration = drift.surfaceDecoration(radius: radius, elevated: elevated);

    final content = Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: decoration,
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: content,
      ),
    );
  }
}
