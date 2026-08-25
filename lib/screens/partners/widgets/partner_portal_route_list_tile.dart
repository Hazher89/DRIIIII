import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/nb_date_format.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';
import '../owner_portal/owner_portal_common.dart';
import 'partner_portal_route_detail_page.dart';
import 'partner_route_pdf_actions.dart';

/// Kompakt rute-rad — trykk for detaljer, hurtigknapp for PDF.
class PartnerPortalRouteListTile extends StatelessWidget {
  final PartnerRouteShare route;
  final Map<String, FleetShiftDefinition> shifts;
  final Future<void> Function() onReload;
  final bool onBehalfOfDriver;
  final String? vehicleLabel;

  const PartnerPortalRouteListTile({
    super.key,
    required this.route,
    required this.shifts,
    required this.onReload,
    this.onBehalfOfDriver = false,
    this.vehicleLabel,
  });

  @override
  Widget build(BuildContext context) {
    final pending = route.requiresAck;
    final day = ownerRouteCalendarDay(route);
    final start = route.routeStartAt != null
        ? NbDateFormat.format(route.routeStartAt!.toLocal(), 'HH:mm')
        : '—';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: pending ? 3 : 0,
      color: pending ? Colors.orange.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: pending ? Colors.orange.shade400 : Colors.black12,
          width: pending ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => PartnerPortalRouteDetailPage.open(
          context,
          route: route,
          shifts: shifts,
          onReload: onReload,
          onBehalfOfDriver: onBehalfOfDriver,
          vehicleLabel: vehicleLabel,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              PartnerRoutePdfActions.ackDot(route, size: 12),
              const SizedBox(width: 10),
              SizedBox(
                width: 56,
                child: Text(
                  start,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: DriftProTheme.accentBlue,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.title ?? 'Rute',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      NbDateFormat.format(day, 'EEE d. MMM'),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    Text(
                      pending ? 'Trykk for å åpne og akseptere' : 'Trykk for å åpne',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: pending ? Colors.orange.shade900 : Colors.grey.shade600,
                      ),
                    ),
                    if (vehicleLabel != null)
                      Text(
                        vehicleLabel!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: DriftProTheme.primaryGreen,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (pending)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'NY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Åpne PDF',
                icon: const Icon(Icons.picture_as_pdf),
                color: DriftProTheme.primaryGreen,
                onPressed: () => PartnerRoutePdfActions.openPdf(context, route),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
