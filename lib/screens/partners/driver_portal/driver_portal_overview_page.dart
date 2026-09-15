import 'package:flutter/material.dart';

import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/user_profile.dart';
import '../owner_portal/owner_portal_common.dart';
import '../widgets/partner_modern_ui.dart';
import '../widgets/partner_portal_page_shell.dart';
import '../widgets/partner_portal_route_detail_page.dart';
import '../widgets/partner_portal_route_list_tile.dart';
import 'driver_portal_common.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import '../../../widgets/home_feed_banner.dart';
import '../../../models/home_feed_item.dart';

class DriverPortalOverviewPage extends StatefulWidget {
  final Partner partner;
  final UserProfile profile;

  const DriverPortalOverviewPage({super.key, required this.partner, required this.profile});

  @override
  State<DriverPortalOverviewPage> createState() => _DriverPortalOverviewPageState();
}

class _DriverPortalOverviewPageState extends State<DriverPortalOverviewPage> {
  DriverPortalData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await DriverPortalData.load(
      partner: widget.partner,
      partnerVehicleId: widget.profile.partnerVehicleId,
    );
    if (mounted) setState(() { _data = d; _loading = false; });
  }

  List<PartnerRouteShare> get _highlightRoutes {
    if (_data == null) return const [];
    final pending = _data!.routes.where((r) => r.requiresAck).toList();
    final today = _data!.routesToday.where((r) => r.ackStatus != 'pending').toList();
    final seen = <String>{};
    final out = <PartnerRouteShare>[];
    for (final r in [...pending, ...today]) {
      if (seen.add(r.id)) out.add(r);
    }
    out.sort((a, b) {
      if (a.requiresAck && !b.requiresAck) return -1;
      if (b.requiresAck && !a.requiresAck) return 1;
      return ownerRouteCalendarDay(a).compareTo(ownerRouteCalendarDay(b));
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final v = _data?.vehicle;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF0F1419) : const Color(0xFFF4F6F8);

    return PartnerPortalPageShell(
      backgroundColor: surface,
      title: widget.partner.name,
      body: _loading || _data == null
          ? const DriftProLoadingCenter()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 100),
                children: [
                  HomeFeedBanner(
                    audience: HomeFeedAudience.partner,
                    portal: 'driver',
                    compact: true,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.local_shipping_outlined,
                            color: DriftProTheme.primaryGreenDark,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v != null
                                    ? 'MAVI ${MaviUnitCodes.normalize(v.unitCode)}'
                                    : 'Sjåfør-portal',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: PartnerModernUi.textPrimary(context),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                v != null
                                    ? '${v.registrationNumber}${v.driverName != null && v.driverName!.trim().isNotEmpty ? ' · ${v.driverName}' : ''}'
                                    : 'Dine tildelte ruter',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: PartnerModernUi.muted(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  PartnerModernKpiGrid(
                    items: [
                      ('Ruter i dag', '${_data!.routesToday.length}'),
                      ('Til svar', '${_data!.pendingAck}'),
                      ('Kommende', '${_data!.routesUpcoming.length}'),
                      ('Arkiv', '${_data!.routesArchive.length}'),
                    ],
                  ),
                  if (_data!.pendingAck > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: FilledButton.icon(
                        onPressed: () {
                          final first = _data!.routes
                              .where((r) => r.requiresAck)
                              .firstOrNull;
                          if (first != null) {
                            PartnerPortalRouteDetailPage.open(
                              context,
                              route: first,
                              shifts: _data!.shiftsById,
                              onReload: _load,
                            );
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                        ),
                        icon: const Icon(Icons.mark_email_unread, size: 28),
                        label: Text(
                          '${_data!.pendingAck} NYE RUTER — TRYKK HER',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  if (_highlightRoutes.isNotEmpty) ...[
                    const OwnerSectionTitle(
                      title: 'Nye og dagens ruter',
                      subtitle: 'Starttid, skift, PDF — aksepter eller avvis med kommentar',
                    ),
                    ..._highlightRoutes.map(
                      (r) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: PartnerPortalRouteListTile(
                          route: r,
                          shifts: _data!.shiftsById,
                          onReload: _load,
                        ),
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: PartnerModernUi.surface(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: PartnerModernUi.border(context)),
                        ),
                        child: Text(
                          _data!.partner.routesOwnerOnly
                              ? 'Ruter for denne bedriften håndteres av bil-eier. '
                                  'Kontakt bil-eier hvis du lurer på ruter.'
                              : 'Ingen ruter i dag. Du får SMS når MAVI tildeler en ny rute.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: PartnerModernUi.muted(context)),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }
}
