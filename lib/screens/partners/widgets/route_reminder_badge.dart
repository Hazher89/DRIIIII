import 'package:flutter/material.dart';

import '../../../models/partner/partner_links.dart';
import '../../../models/partner/route_reminder_flag.dart';

/// Tydelig badge når purring er sendt til partner som ikke har akseptert ruten.
class RouteReminderBadge extends StatelessWidget {
  final PartnerRouteShare share;
  final RouteReminderFlag? flag;
  final bool compact;

  const RouteReminderBadge({
    super.key,
    required this.share,
    this.flag,
    this.compact = false,
  });

  bool get _visible {
    if (flag == null || !flag!.hasAnyReminder) return false;
    if (share.ackStatus != 'pending') return false;
    if (share.isStaged || share.isRegistered) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final f = flag!;
    final label = f.badgeLabel;
    final bg = Colors.deepOrange.shade50;
    final fg = Colors.deepOrange.shade900;
    final border = Colors.deepOrange.shade300;

    final icon = f.hasSmsReminder && f.hasEmailReminder
        ? Icons.notifications_active
        : f.hasSmsReminder
            ? Icons.sms_outlined
            : Icons.email_outlined;

    if (compact) {
      return Tooltip(
        message: 'Purring sendt: ${f.tooltipDetail}',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: fg),
              const SizedBox(width: 3),
              Text(
                'Purring',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: fg,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Tooltip(
      message: 'Purring sendt til bedrift som ikke har akseptert.\n${f.tooltipDetail}',
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.deepOrange.withValues(alpha: 0.12),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: fg,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
