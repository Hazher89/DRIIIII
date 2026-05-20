import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';
import '../widgets/partner_route_pdf_actions.dart';
import 'owner_portal_common.dart';
import 'owner_portal_route_actions.dart';

class OwnerPortalRouteCard extends StatelessWidget {
  final PartnerRouteShare route;
  final PartnerVehicle? vehicle;
  final Map<String, FleetShiftDefinition> shifts;
  final Future<void> Function() onReload;
  final bool onBehalfOfDriver;

  const OwnerPortalRouteCard({
    super.key,
    required this.route,
    required this.vehicle,
    required this.shifts,
    required this.onReload,
    this.onBehalfOfDriver = true,
  });

  @override
  Widget build(BuildContext context) {
    final day = ownerRouteCalendarDay(route);
    final area = ownerRouteArea(route, shifts);
    final pending = route.ackStatus == 'pending';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: pending
              ? Colors.orange.withValues(alpha: 0.45)
              : (Theme.of(context).brightness == Brightness.dark ? Colors.white12 : Colors.black12),
          width: pending ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                _StatusPill(status: route.ackStatus),
              ],
            ),
            const SizedBox(height: 10),
            if (vehicle != null)
              Text(
                '${MaviUnitCodes.normalize(vehicle!.unitCode)} · ${vehicle!.registrationNumber}'
                '${vehicle!.driverName != null && vehicle!.driverName!.trim().isNotEmpty ? ' · ${vehicle!.driverName}' : ''}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: DriftProTheme.primaryGreen,
                  fontSize: 13,
                ),
              ),
            const SizedBox(height: 8),
            if (area != (shifts[route.shiftId]?.name ?? ''))
              _infoRow(Icons.map_outlined, 'Område', area),
            if (route.shiftId != null)
              _infoRow(
                Icons.category_outlined,
                'Skifttype',
                portalShiftTypeLabel(shifts[route.shiftId]),
              ),
            _infoRow(
              Icons.calendar_today_outlined,
              'Rutedag',
              DateFormat('EEEE d. MMM yyyy', 'nb').format(day),
            ),
            if (route.routeStartAt != null) ...[
              const SizedBox(height: 4),
              Center(
                child: Text(
                  DateFormat('HH:mm', 'nb').format(route.routeStartAt!.toLocal()),
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: DriftProTheme.accentBlue,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'Starttid',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                ),
              ),
            ],
            if (route.shiftId != null)
              _infoRow(Icons.route_outlined, 'Skift', shifts[route.shiftId]?.name ?? '—', bold: true),
            if ((route.notes ?? '').trim().isNotEmpty)
              _infoRow(Icons.notes_outlined, 'Notat fra MAVI', route.notes!.trim()),
            if ((route.ackComment ?? '').trim().isNotEmpty)
              _infoRow(Icons.chat_bubble_outline, 'Tilbakemelding', route.ackComment!.trim()),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => PartnerRoutePdfActions.openPdf(context, route),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Åpne rute-PDF'),
              ),
            ),
            if (pending) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => ownerPortalSetRouteAck(
                        context,
                        route,
                        accepted: true,
                        onDone: onReload,
                        onBehalfOfDriver: onBehalfOfDriver,
                      ),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Godkjenn'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => ownerPortalSetRouteAck(
                        context,
                        route,
                        accepted: false,
                        onDone: onReload,
                        onBehalfOfDriver: onBehalfOfDriver,
                      ),
                      icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                      label: Text(onBehalfOfDriver ? 'Avvis' : 'Avlys'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {bool highlight = false, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: highlight ? DriftProTheme.accentBlue : Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: highlight ? 18 : (bold ? 16 : 14),
                    fontWeight: highlight || bold ? FontWeight.w800 : FontWeight.w600,
                    color: highlight ? DriftProTheme.accentBlue : (bold ? DriftProTheme.primaryGreen : null),
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
        label = 'Godkjent';
        bg = Colors.green.withValues(alpha: 0.15);
        fg = Colors.green.shade800;
        break;
      case 'rejected':
        label = 'Avvist';
        bg = Colors.red.withValues(alpha: 0.12);
        fg = Colors.red.shade800;
        break;
      default:
        label = 'Venter';
        bg = Colors.orange.withValues(alpha: 0.15);
        fg = Colors.orange.shade900;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}
