import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Bruksmåler som går fra gull (lav bruk) til rødt (brukt opp).
class LeaveUsageMeter extends StatelessWidget {
  const LeaveUsageMeter({
    super.key,
    required this.title,
    required this.used,
    required this.max,
    this.subtitle,
    this.icon = Icons.local_hospital_outlined,
    this.trailing,
  });

  final String title;
  final int used;
  final int max;
  final String? subtitle;
  final IconData icon;
  final Widget? trailing;

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

    return Container(
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
                '$used/$max',
                style: DriftProTheme.labelLg.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _ratio,
              minHeight: 10,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            remaining <= 0
                ? 'Kvoten er brukt opp i denne perioden'
                : '$remaining dager igjen i perioden',
            style: DriftProTheme.bodySm.copyWith(
              color: remaining <= 0 ? color : null,
              fontWeight: remaining <= 0 ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
