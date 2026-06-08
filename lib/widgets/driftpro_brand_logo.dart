import 'package:flutter/material.dart';

import '../core/constants/driftpro_brand.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/driftpro_theme_context.dart';

enum DriftProBrandDensity { compact, header, comfortable, hero }

/// DriftPro-logo med valgfri undertekst.
class DriftProBrandLogo extends StatelessWidget {
  const DriftProBrandLogo({
    super.key,
    this.density = DriftProBrandDensity.compact,
    this.showSubtitle = true,
    this.alignment = Alignment.centerLeft,
  });

  final DriftProBrandDensity density;
  final bool showSubtitle;
  final Alignment alignment;

  double get _logoHeight {
    switch (density) {
      case DriftProBrandDensity.compact:
        return 22;
      case DriftProBrandDensity.header:
        return 40;
      case DriftProBrandDensity.comfortable:
        return 48;
      case DriftProBrandDensity.hero:
        return 64;
    }
  }

  double get _subtitleSize {
    switch (density) {
      case DriftProBrandDensity.compact:
        return 8.5;
      case DriftProBrandDensity.header:
        return 10;
      case DriftProBrandDensity.comfortable:
        return 10.5;
      case DriftProBrandDensity.hero:
        return 12;
    }
  }

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitleColor = isDark ? drift.textMuted : Colors.grey[600];

    return Align(
      alignment: alignment,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: alignment == Alignment.center
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Image.asset(
            DriftProBrand.logoPrimary,
            height: _logoHeight,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
          if (showSubtitle) ...[
            SizedBox(
              height: switch (density) {
                DriftProBrandDensity.compact => 1,
                DriftProBrandDensity.header => 2,
                _ => 3,
              },
            ),
            Text(
              DriftProBrand.subtitle,
              textAlign: alignment == Alignment.center ? TextAlign.center : TextAlign.start,
              style: DriftProTheme.caption.copyWith(
                fontSize: _subtitleSize,
                height: 1.2,
                letterSpacing: 0.15,
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
