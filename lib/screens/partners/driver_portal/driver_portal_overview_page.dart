import 'package:flutter/material.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/user_profile.dart';
import '../owner_portal/owner_portal_common.dart';
import '../partner_shell.dart';
import '../widgets/partner_modern_ui.dart';
import '../widgets/partner_ui.dart';
import 'driver_portal_common.dart';
import 'driver_portal_route_card.dart';

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
    final pending = _data!.routes.where((r) => r.ackStatus == 'pending').toList();
    final today = _data!.routesToday.where((r) => r.ackStatus != 'pending').toList();
    final seen = <String>{};
    final out = <PartnerRouteShare>[];
    for (final r in [...pending, ...today]) {
      if (seen.add(r.id)) out.add(r);
    }
    out.sort((a, b) {
      if (a.ackStatus == 'pending' && b.ackStatus != 'pending') return -1;
      if (b.ackStatus == 'pending' && a.ackStatus != 'pending') return 1;
      return ownerRouteCalendarDay(a).compareTo(ownerRouteCalendarDay(b));
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final v = _data?.vehicle;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF0F1419) : const Color(0xFFF4F6F8);

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.partner.name, style: const TextStyle(fontSize: 16)),
            const Text(
              kDriverPortalBuildLabel,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: DriftProTheme.accentBlue),
            ),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Oppdater', onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            tooltip: 'Logg ut',
            icon: const Icon(Icons.logout),
            onPressed: () => signOutFromPortal(context),
          ),
        ],
      ),
      body: _loading || _data == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 100),
                children: [
                  PartnerHeroBanner(
                    title: v != null
                        ? 'MAVI ${MaviUnitCodes.normalize(v.unitCode)}'
                        : 'Sjåfør-portal',
                    subtitle: v != null
                        ? '${v.registrationNumber}${v.driverName != null && v.driverName!.trim().isNotEmpty ? ' · ${v.driverName}' : ''}'
                        : 'Dine tildelte ruter',
                    leading: const Icon(Icons.local_shipping_outlined, color: Colors.white, size: 32),
                  ),
                  PartnerSmartActionsPanel(
                    title: 'Anbefalte handlinger',
                    actions: [
                      PartnerSmartAction(
                        label: 'Svar på ${_data!.pendingAck} ventende ruter',
                        hint: 'Aksepter eller avvis med kommentar',
                        icon: Icons.mark_email_unread_outlined,
                      ),
                      const PartnerSmartAction(
                        label: 'Sjekk dagens rute-PDF',
                        hint: 'Bekreft starttid og kundeliste før oppdrag',
                        icon: Icons.picture_as_pdf_outlined,
                      ),
                    ],
                  ),
                  if (_highlightRoutes.isNotEmpty) ...[
                    const OwnerSectionTitle(
                      title: 'Nye og dagens ruter',
                      subtitle: 'Starttid, skift, PDF — aksepter eller avvis med kommentar',
                    ),
                    ..._highlightRoutes.map(
                      (r) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DriverPortalRouteCard(
                          route: r,
                          shifts: _data!.shiftsById,
                          onReload: _load,
                        ),
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            _data!.partner.routesOwnerOnly
                                ? 'Ruter for denne bedriften håndteres av bil-eier. '
                                    'Kontakt bil-eier hvis du lurer på ruter.'
                                : 'Ingen ruter i dag. Du får SMS når MAVI tildeler en ny rute.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: PartnerUi.mutedText(context)),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.25,
                      children: [
                        OwnerKpiCard(
                          label: 'Ruter i dag',
                          value: '${_data!.routesToday.length}',
                          icon: Icons.today,
                          accent: DriftProTheme.accentBlue,
                        ),
                        OwnerKpiCard(
                          label: 'Til svar',
                          value: '${_data!.pendingAck}',
                          icon: Icons.hourglass_top,
                          accent: _data!.pendingAck > 0 ? Colors.orange : Colors.grey,
                        ),
                        OwnerKpiCard(
                          label: 'Kommende',
                          value: '${_data!.routesUpcoming.length}',
                          icon: Icons.upcoming,
                        ),
                        OwnerKpiCard(
                          label: 'Arkiv',
                          value: '${_data!.routesArchive.length}',
                          icon: Icons.inventory_2_outlined,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
