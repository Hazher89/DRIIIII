import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/nb_date_format.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';
import '../owner_portal/owner_portal_common.dart';
import 'partner_route_pdf_actions.dart';
import 'partner_route_support_contact.dart';

/// Fullskjerm rutedetalj — én tydelig vei: PDF → aksepter.
class PartnerPortalRouteDetailPage extends StatelessWidget {
  final PartnerRouteShare route;
  final Map<String, FleetShiftDefinition> shifts;
  final Future<void> Function() onReload;
  final bool onBehalfOfDriver;
  final String? vehicleLabel;

  const PartnerPortalRouteDetailPage({
    super.key,
    required this.route,
    required this.shifts,
    required this.onReload,
    this.onBehalfOfDriver = false,
    this.vehicleLabel,
  });

  static Future<void> open(
    BuildContext context, {
    required PartnerRouteShare route,
    required Map<String, FleetShiftDefinition> shifts,
    required Future<void> Function() onReload,
    bool onBehalfOfDriver = false,
    String? vehicleLabel,
    bool openPdfImmediately = false,
  }) async {
    if (openPdfImmediately && route.requiresAck) {
      await PartnerRoutePdfActions.openPdfWithAcceptFlow(
        context,
        share: route,
        onBehalfOfDriver: onBehalfOfDriver,
        onReload: onReload,
      );
      return;
    }
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PartnerPortalRouteDetailPage(
          route: route,
          shifts: shifts,
          onReload: onReload,
          onBehalfOfDriver: onBehalfOfDriver,
          vehicleLabel: vehicleLabel,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = route.requiresAck;
    final day = ownerRouteCalendarDay(route);
    final area = ownerRouteArea(route, shifts);
    final shiftName = route.shiftId != null ? shifts[route.shiftId]?.name : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(route.title ?? 'Rute', overflow: TextOverflow.ellipsis),
      ),
      bottomNavigationBar: pending
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final accepted = await PartnerRoutePdfActions.openPdfWithAcceptFlow(
                        context,
                        share: route,
                        onBehalfOfDriver: onBehalfOfDriver,
                        onReload: onReload,
                      );
                      if (accepted && context.mounted) Navigator.pop(context);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: DriftProTheme.primaryGreen,
                    ),
                    icon: const Icon(Icons.picture_as_pdf, size: 28),
                    label: const Text(
                      'Les PDF og aksepter',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (pending)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange.shade300, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.notifications_active, color: Colors.orange.shade800, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Ny rute!',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Trykk «Les PDF og aksepter» nederst. '
                    'Du leser ruten i appen og bekrefter med ett trykk.',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade900,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          if (pending) const SizedBox(height: 20),
          Text(
            NbDateFormat.format(day, 'EEEE d. MMMM yyyy'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          if (route.routeStartAt != null)
            Text(
              NbDateFormat.format(route.routeStartAt!.toLocal(), 'HH:mm'),
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w900,
                height: 1,
                color: DriftProTheme.accentBlue,
                letterSpacing: 1,
              ),
            )
          else
            Text(
              'Starttid ikke satt',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade600,
              ),
            ),
          const SizedBox(height: 4),
          const Text('Starttid', style: TextStyle(fontWeight: FontWeight.w600)),
          if (vehicleLabel != null) ...[
            const SizedBox(height: 16),
            _info(Icons.local_shipping_outlined, 'Kjøretøy', vehicleLabel!),
          ],
          if (shiftName != null) _info(Icons.route_outlined, 'Skift', shiftName),
          if (area != (shiftName ?? '')) _info(Icons.map_outlined, 'Område', area),
          if ((route.notes ?? '').trim().isNotEmpty)
            _info(Icons.notes_outlined, 'Notat fra MAVI', route.notes!.trim()),
          const SizedBox(height: 24),
          if (!pending) ...[
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () => PartnerRoutePdfActions.openPdf(context, route),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Åpne rute-PDF', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 12),
            if (route.ackStatus == 'accepted')
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Ruten er akseptert',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.green.shade800,
                    ),
                  ),
                ],
              ),
          ],
          if (pending) ...[
            const PartnerRouteSupportContactCard(),
            const SizedBox(height: 88),
          ],
        ],
      ),
    );
  }

  Widget _info(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: DriftProTheme.primaryGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
