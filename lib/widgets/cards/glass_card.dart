import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// A glass-morphism-inspired card used for premium hero sections.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final double? height;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.gradient,
    this.onTap,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          gradient: gradient ?? DriftProTheme.primaryGradient,
          borderRadius: BorderRadius.circular(DriftProTheme.radiusXl),
          boxShadow: DriftProTheme.elevatedShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(DriftProTheme.radiusXl),
          child: Stack(
            children: [
              // Subtle light overlay for glass feel
              Positioned(
                top: -30,
                right: -30,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.06),
                  ),
                ),
              ),
              Positioned(
                bottom: -40,
                left: -20,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.04),
                  ),
                ),
              ),
              Padding(
                padding: padding ??
                    const EdgeInsets.all(DriftProTheme.spacingLg),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
