import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/driftpro_theme_context.dart';

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
    final drift = context.driftColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Text(
            title,
            style: DriftProTheme.headingSm.copyWith(color: drift.textPrimary),
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
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (actionIcon != null) ...[
                    const SizedBox(width: 4),
                    Icon(
                      actionIcon,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
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
