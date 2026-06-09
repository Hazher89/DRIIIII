import 'package:flutter/material.dart';

import '../core/constants/driftpro_brand.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/driftpro_theme_context.dart';
import 'driftpro_animated_icon.dart';

enum DriftProBrandDensity { compact, header, comfortable, hero }

/// DriftPro-logo: animert D-ikon + ordmerke + undertekst.
class DriftProBrandLogo extends StatelessWidget {
  const DriftProBrandLogo({
    super.key,
    this.density = DriftProBrandDensity.compact,
    this.showSubtitle = true,
    this.alignment = Alignment.centerLeft,
    this.animateIcon = true,
  });

  final DriftProBrandDensity density;
  final bool showSubtitle;
  final Alignment alignment;
  final bool animateIcon;

  double get _iconSize {
    switch (density) {
      case DriftProBrandDensity.compact:
        return 34;
      case DriftProBrandDensity.header:
        return 54;
      case DriftProBrandDensity.comfortable:
        return 52;
      case DriftProBrandDensity.hero:
        return 68;
    }
  }

  double get _wordmarkSize {
    switch (density) {
      case DriftProBrandDensity.compact:
        return 18;
      case DriftProBrandDensity.header:
        return 24;
      case DriftProBrandDensity.comfortable:
        return 30;
      case DriftProBrandDensity.hero:
        return 38;
    }
  }

  double get _subtitleSize {
    switch (density) {
      case DriftProBrandDensity.compact:
        return 9;
      case DriftProBrandDensity.header:
        return 11;
      case DriftProBrandDensity.comfortable:
        return 11.5;
      case DriftProBrandDensity.hero:
        return 13;
    }
  }

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitleColor = isDark ? drift.textMuted : Colors.grey[600];
    final driftColor = isDark ? Colors.white : const Color(0xFF2D3436);

    return Align(
      alignment: alignment,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: alignment == Alignment.center
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              animateIcon
                  ? DriftProAnimatedIcon(
                      size: _iconSize,
                      motion: DriftProIconMotion.ambient,
                    )
                  : Image.asset(
                      DriftProBrand.logoMark,
                      width: _iconSize,
                      height: _iconSize,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
              SizedBox(width: density == DriftProBrandDensity.header ? 10 : 8),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: _wordmarkSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1,
                  ),
                  children: [
                    TextSpan(
                      text: 'Drift',
                      style: TextStyle(color: driftColor),
                    ),
                    TextSpan(
                      text: 'Pro',
                      style: TextStyle(color: DriftProTheme.primaryGreen),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showSubtitle) ...[
            SizedBox(height: density == DriftProBrandDensity.header ? 4 : 3),
            Text(
              DriftProBrand.subtitle,
              textAlign: alignment == Alignment.center ? TextAlign.center : TextAlign.start,
              style: DriftProTheme.caption.copyWith(
                fontSize: _subtitleSize,
                height: 1.2,
                letterSpacing: 0.1,
                color: subtitleColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
