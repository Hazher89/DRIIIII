import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/partner/route_send_summary.dart';

/// Fin, kort utsendingsrapport med sjåførlinjer + OK-knapp.
Future<void> showRouteSendSummaryDialog({
  required BuildContext context,
  required RouteSendSummary summary,
  String title = 'Ruter sendt',
  bool showOk = true,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PartnerRouteSendSummaryDialog(
      summary: summary,
      title: title,
      showOk: showOk,
    ),
  );
}

class PartnerRouteSendSummaryDialog extends StatelessWidget {
  const PartnerRouteSendSummaryDialog({
    super.key,
    required this.summary,
    this.title = 'Ruter sendt',
    this.showOk = true,
  });

  final RouteSendSummary summary;
  final String title;
  final bool showOk;

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('d. MMM yyyy · HH:mm', 'nb');
    final dayFmt = DateFormat('EEEE d. MMMM yyyy', 'nb');
    final sentLabel = summary.sentAt != null
        ? timeFmt.format(summary.sentAt!.toLocal())
        : null;
    final dayLabel = summary.routeDate != null
        ? dayFmt.format(summary.routeDate!)
        : null;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      title: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: const BoxDecoration(
          color: DriftProTheme.primaryGreen,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              summary.headline,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontWeight: FontWeight.w700,
                fontSize: 14,
                height: 1.3,
              ),
            ),
            if (dayLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                'Rutedato: $dayLabel',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 12,
                ),
              ),
            ],
            if (sentLabel != null) ...[
              const SizedBox(height: 2),
              Text(
                'Sendt: $sentLabel',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      content: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.5,
          ),
          child: summary.drivers.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Ingen sjåførlinjer å vise.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: summary.drivers.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: Colors.grey.shade200,
                  ),
                  itemBuilder: (context, i) {
                    final line = summary.drivers[i];
                    final multi = line.routeCount > 1;
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: multi
                            ? const Color(0xFF7B1FA2).withValues(alpha: 0.12)
                            : DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                        child: Text(
                          line.shortMavi,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: multi
                                ? const Color(0xFF7B1FA2)
                                : DriftProTheme.primaryGreen,
                          ),
                        ),
                      ),
                      title: Text(
                        line.summaryLine,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                      subtitle: (line.driverName ?? line.partnerName) == null
                          ? null
                          : Text(
                              (line.driverName ?? line.partnerName)!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade700,
                              ),
                            ),
                      trailing: multi
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF7B1FA2)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${line.routeCount} last',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF7B1FA2),
                                ),
                              ),
                            )
                          : Icon(
                              Icons.check_rounded,
                              color: Colors.green.shade700,
                              size: 20,
                            ),
                    );
                  },
                ),
        ),
      ),
      actions: [
        if (showOk)
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'OK',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ),
      ],
    );
  }
}
