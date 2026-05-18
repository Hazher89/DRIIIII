import 'package:flutter/material.dart';

import '../../../core/constants/leave_rules.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/absence.dart';

class LeaveRulesPanel extends StatelessWidget {
  final AbsenceType? highlightType;
  final bool compact;

  const LeaveRulesPanel({
    super.key,
    this.highlightType,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cards = LeaveRules.cardsForType(highlightType);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.gavel_rounded, size: 18, color: DriftProTheme.primaryGreen),
            const SizedBox(width: 8),
            Text(
              'Regler (Lovdata)',
              style: DriftProTheme.labelLg.copyWith(
                color: isDark ? Colors.white : Colors.grey[900],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...cards.map((c) => _RuleTile(card: c, isDark: isDark, compact: compact)),
      ],
    );
  }
}

class _RuleTile extends StatelessWidget {
  final LeaveRuleCard card;
  final bool isDark;
  final bool compact;

  const _RuleTile({
    required this.card,
    required this.isDark,
    required this.compact,
  });

  IconData get _icon {
    switch (card.iconName) {
      case 'child':
        return Icons.child_care_rounded;
      case 'sun':
        return Icons.wb_sunny_rounded;
      default:
        return Icons.person_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon, color: DriftProTheme.primaryGreen, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.title, style: DriftProTheme.labelLg),
                const SizedBox(height: 6),
                Text(
                  card.body,
                  style: DriftProTheme.bodySm.copyWith(
                    height: 1.45,
                    color: isDark ? Colors.white70 : Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
