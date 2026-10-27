import 'package:flutter/material.dart';

import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/nb_date_format.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';
import '../owner_portal/owner_portal_common.dart';
import 'partner_portal_route_detail_page.dart';
import 'partner_route_pdf_actions.dart';

/// Kompakt rute-rad — trykk for å lese PDF og akseptere.
class PartnerPortalRouteListTile extends StatelessWidget {
  final PartnerRouteShare route;
  final Map<String, FleetShiftDefinition> shifts;
  final Future<void> Function() onReload;
  final bool onBehalfOfDriver;
  final String? vehicleLabel;
  /// Rå enhetskode (NO_O_M0096) — brukes til ren M0096-tittel.
  final String? unitCode;
  /// F.eks. «Last A» når samme bil har flere ruter samme dag.
  final String? loadBadge;

  const PartnerPortalRouteListTile({
    super.key,
    required this.route,
    required this.shifts,
    required this.onReload,
    this.onBehalfOfDriver = false,
    this.vehicleLabel,
    this.unitCode,
    this.loadBadge,
  });

  @override
  Widget build(BuildContext context) {
    final pending = route.requiresAck;
    final day = ownerRouteCalendarDay(route);
    final start = route.routeStartAt != null
        ? NbDateFormat.format(route.routeStartAt!.toLocal(), 'HH:mm')
        : '—';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mavi = portalRouteMaviLabel(route, unitCode: unitCode);
    final dateLine = NbDateFormat.format(day, 'EEEE d. MMMM');
    final plate = _plateOnly(vehicleLabel);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: pending ? 2 : 0,
      color: pending
          ? (isDark ? Colors.orange.shade900.withValues(alpha: 0.22) : Colors.orange.shade50)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: pending ? Colors.orange.shade400 : Colors.black12,
          width: pending ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: DriftProTheme.accentBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        start,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: DriftProTheme.accentBlue,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      PartnerRoutePdfActions.ackDot(route, size: 10),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              mavi,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (loadBadge != null && loadBadge!.trim().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6A1B9A).withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                loadBadge!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF6A1B9A),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateLine,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      if (plate != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          plate,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: DriftProTheme.primaryGreen,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: pending
                        ? Colors.orange.shade200
                        : DriftProTheme.primaryGreen.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    pending ? 'NY' : 'Akseptert',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: pending
                          ? Colors.orange.shade900
                          : DriftProTheme.primaryGreen,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (pending)
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => PartnerRoutePdfActions.openPdfWithAcceptFlow(
                    context,
                    share: route,
                    onBehalfOfDriver: onBehalfOfDriver,
                    onReload: onReload,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: DriftProTheme.primaryGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.picture_as_pdf, size: 20),
                  label: const Text(
                    'Les PDF og aksepter',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => PartnerRoutePdfActions.openPdf(context, route),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Åpne PDF'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Detaljer',
                    onPressed: () => PartnerPortalRouteDetailPage.open(
                      context,
                      route: route,
                      shifts: shifts,
                      onReload: onReload,
                      onBehalfOfDriver: onBehalfOfDriver,
                      vehicleLabel: vehicleLabel,
                    ),
                    icon: const Icon(Icons.info_outline),
                  ),
                ],
              ),
            if (pending) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => PartnerPortalRouteDetailPage.open(
                  context,
                  route: route,
                  shifts: shifts,
                  onReload: onReload,
                  onBehalfOfDriver: onBehalfOfDriver,
                  vehicleLabel: vehicleLabel,
                ),
                child: const Text('Se rutedetaljer'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? _plateOnly(String? label) {
    if (label == null || label.trim().isEmpty) return null;
    // "NO_O_M0096 · AB12345" eller "M0096 · AB12345" → bare skilt
    final parts = label.split('·').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) {
      final last = parts.last;
      if (!last.toUpperCase().startsWith('NO_O_') && !RegExp(r'^M\d+$').hasMatch(last)) {
        return last;
      }
    }
    // Hvis label er ren MAVI-kode, ikke vis den på nytt.
    if (MaviUnitCodes.extractShortLabel(label) != null &&
        parts.length == 1 &&
        RegExp(r'^(NO_O_)?M\d+$', caseSensitive: false).hasMatch(parts.first.replaceAll(' ', ''))) {
      return null;
    }
    return label;
  }
}
