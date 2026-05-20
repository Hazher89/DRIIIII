import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/nb_date_format.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';
import '../owner_portal/owner_portal_common.dart';
import '../owner_portal/owner_portal_route_actions.dart';
import '../widgets/partner_route_pdf_actions.dart';

/// Rute-kort for sjåfør — stor starttid, skift, PDF, aksepter / avlys.
class DriverPortalRouteCard extends StatelessWidget {
  final PartnerRouteShare route;
  final Map<String, FleetShiftDefinition> shifts;
  final Future<void> Function() onReload;
  final bool compactActions;

  const DriverPortalRouteCard({
    super.key,
    required this.route,
    required this.shifts,
    required this.onReload,
    this.compactActions = false,
  });

  String get _shiftName {
    final sid = route.shiftId;
    if (sid == null) return '—';
    return shifts[sid]?.name ?? '—';
  }

  @override
  Widget build(BuildContext context) {
    final day = ownerRouteCalendarDay(route);
    final area = ownerRouteArea(route, shifts);
    final pending = route.ackStatus == 'pending';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1A2332) : Colors.white;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: isDark ? 0 : 2,
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: pending
              ? Colors.orange.shade400
              : (isDark ? Colors.white24 : Colors.black12),
          width: pending ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PartnerRoutePdfActions.ackDot(route, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    route.title ?? 'Rute',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                _StatusPill(status: route.ackStatus),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: DriftProTheme.accentBlue.withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    NbDateFormat.format(day, 'EEEE d. MMMM yyyy'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                  ),
                  if (route.routeStartAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'START ${NbDateFormat.format(route.routeStartAt!.toLocal(), 'HH:mm')}',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                        color: DriftProTheme.accentBlue,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Starttid ikke satt',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _line(Icons.route_outlined, 'Skift', _shiftName, bold: true),
            if (area != _shiftName && area != '—') _line(Icons.map_outlined, 'Område', area),
            if ((route.notes ?? '').trim().isNotEmpty)
              _line(Icons.notes_outlined, 'Notat fra MAVI', route.notes!.trim()),
            if ((route.ackComment ?? '').trim().isNotEmpty)
              _line(Icons.chat_bubble_outline, 'Din kommentar', route.ackComment!.trim()),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => PartnerRoutePdfActions.openPdf(context, route),
                style: FilledButton.styleFrom(
                  backgroundColor: DriftProTheme.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Åpne rute-PDF', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            if (pending) ...[
              const SizedBox(height: 12),
              if (!compactActions)
                FilledButton.icon(
                  onPressed: () => ownerPortalSetRouteAck(
                    context,
                    route,
                    accepted: true,
                    onDone: onReload,
                    onBehalfOfDriver: false,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Aksepter rute', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              if (!compactActions) const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => ownerPortalSetRouteAck(
                  context,
                  route,
                  accepted: false,
                  onDone: onReload,
                  onBehalfOfDriver: false,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade400, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text(
                  'Ikke aksepter (med kommentar)',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: DriftProTheme.primaryGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: bold ? 16 : 14,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: bold ? DriftProTheme.primaryGreen : null,
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

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    late String label;
    late Color bg;
    late Color fg;
    switch (status) {
      case 'accepted':
        label = 'Akseptert';
        bg = Colors.green.withValues(alpha: 0.15);
        fg = Colors.green.shade800;
        break;
      case 'rejected':
        label = 'Avvist';
        bg = Colors.red.withValues(alpha: 0.12);
        fg = Colors.red.shade800;
        break;
      default:
        label = 'Ny — svar';
        bg = Colors.orange.withValues(alpha: 0.2);
        fg = Colors.orange.shade900;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}
