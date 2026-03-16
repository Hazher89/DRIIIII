import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Section header with optional action button.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Text(
            title,
            style: DriftProTheme.headingSm.copyWith(
              color: isDark ? Colors.white : Colors.grey[900],
            ),
          ),
          const Spacer(),
          if (actionLabel != null || actionIcon != null)
            GestureDetector(
              onTap: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (actionLabel != null)
                    Text(
                      actionLabel!,
                      style: DriftProTheme.bodySm.copyWith(
                        color: DriftProTheme.primaryGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (actionIcon != null) ...[
                    const SizedBox(width: 4),
                    Icon(
                      actionIcon,
                      size: 16,
                      color: DriftProTheme.primaryGreen,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
