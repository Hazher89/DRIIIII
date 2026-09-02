import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Bruksmåler — gull → rødt. Støtter dobbel metrikk (dager + tilfeller).
class LeaveUsageMeter extends StatelessWidget {
  const LeaveUsageMeter({
    super.key,
    required this.title,
    required this.used,
    required this.max,
    this.subtitle,
    this.icon = Icons.local_hospital_outlined,
    this.trailing,
    this.metricLabel,
    this.secondaryUsed,
    this.secondaryMax,
    this.secondaryMetricLabel,
    this.secondaryRemainingLabel,
    this.onTap,
  });

  final String title;
  final int used;
  final int max;
  final String? subtitle;
  final IconData icon;
  final Widget? trailing;
  /// Overstyrer standard «used/max» (f.eks. «4 dager · 3/4 tilfeller»).
  final String? metricLabel;
  /// Valgfri sekundær måler (f.eks. tilfeller ved egenmelding).
  final int? secondaryUsed;
  final int? secondaryMax;
  final String? secondaryMetricLabel;
  final String? secondaryRemainingLabel;
  final VoidCallback? onTap;

  double get _ratio {
    if (max <= 0) return 1;
    return (used / max).clamp(0.0, 1.0);
  }

  Color get _meterColor {
    final t = _ratio;
    if (t <= 0.35) {
      return Color.lerp(const Color(0xFFD4A017), const Color(0xFFE8B923), t / 0.35)!;
    }
    if (t <= 0.7) {
      return Color.lerp(const Color(0xFFE8B923), const Color(0xFFE67E22), (t - 0.35) / 0.35)!;
    }
    return Color.lerp(const Color(0xFFE67E22), const Color(0xFFC0392B), (t - 0.7) / 0.3)!;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _meterColor;
    final remaining = (max - used).clamp(0, max);

    final body = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: DriftProTheme.labelLg),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: DriftProTheme.caption),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              Text(
                metricLabel ?? '$used/$max',
                style: DriftProTheme.labelLg.copyWith(color: color),
                textAlign: TextAlign.end,
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: color.withValues(alpha: 0.7), size: 20),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _meterRow(
            label: secondaryMax != null ? 'Dager' : null,
            used: used,
            max: max,
            color: color,
          ),
          if (secondaryMax != null && secondaryUsed != null) ...[
            const SizedBox(height: 10),
            _meterRow(
              label: 'Tilfeller',
              used: secondaryUsed!,
              max: secondaryMax!,
              color: color,
              valueLabel: secondaryMetricLabel,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            _footerText(remaining, color),
            style: DriftProTheme.bodySm.copyWith(
              color: remaining <= 0 ? color : null,
              fontWeight: remaining <= 0 ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          if (secondaryMax != null &&
              secondaryUsed != null &&
              secondaryRemainingLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              secondaryRemainingLabel!,
              style: DriftProTheme.caption,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return body;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: body,
      ),
    );
  }

  String _footerText(int remaining, Color color) {
    if (remaining <= 0) return 'Dagskvoten er brukt opp i denne perioden';
    return '$remaining dager igjen i perioden';
  }

  Widget _meterRow({
    required int used,
    required int max,
    required Color color,
    String? label,
    String? valueLabel,
  }) {
    final ratio = max <= 0 ? 1.0 : (used / max).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: DriftProTheme.caption),
              Text(
                valueLabel ?? '$used/$max',
                style: DriftProTheme.caption.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: label == null ? 10 : 8,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
