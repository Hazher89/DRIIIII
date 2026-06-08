import 'package:flutter/material.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/user_profile.dart';
import '../widgets/partner_portal_route_list_tile.dart';
import 'driver_portal_common.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

class DriverPortalRoutesPage extends StatefulWidget {
  final Partner partner;
  final UserProfile profile;

  const DriverPortalRoutesPage({super.key, required this.partner, required this.profile});

  @override
  State<DriverPortalRoutesPage> createState() => _DriverPortalRoutesPageState();
}

class _DriverPortalRoutesPageState extends State<DriverPortalRoutesPage> {
  int _tab = 0;
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
    if (mounted) {
      setState(() {
        _data = d;
        _loading = false;
        if (d.pendingAck > 0) _tab = -1;
      });
    }
  }

  List<PartnerRouteShare> get _pending =>
      _data?.routes.where((r) => r.ackStatus == 'pending').toList() ?? [];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF0F1419) : const Color(0xFFF4F6F8);
    final pending = _pending;

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Mine ruter'),
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
          ? const DriftProLoadingCenter()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pending.isNotEmpty)
                  Material(
                    color: Colors.orange.shade100,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(Icons.mark_email_unread, color: Colors.orange.shade900, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${pending.length} rute(r) venter — trykk på ruten, åpne PDF og aksepter',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: SegmentedButton<int>(
                    segments: [
                      if (pending.isNotEmpty)
                        ButtonSegment(value: -1, label: Text('Venter (${pending.length})')),
                      ButtonSegment(value: 0, label: Text('I dag (${_data!.routesToday.length})')),
                      ButtonSegment(value: 1, label: Text('Kommende (${_data!.routesUpcoming.length})')),
                      ButtonSegment(value: 2, label: Text('Arkiv (${_data!.routesArchive.length})')),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                ),
                Expanded(
                  child: switch (_tab) {
                    -1 => _routeList(pending, 'Ingen ruter venter.'),
                    0 => _routeList(_data!.routesToday, 'Ingen ruter i dag.'),
                    1 => _routeList(_data!.routesUpcoming, 'Ingen kommende ruter.'),
                    _ => _routeList(_data!.routesArchive, 'Ingen ruter i arkivet.'),
                  },
                ),
              ],
            ),
    );
  }

  Widget _routeList(List<PartnerRouteShare> routes, String empty) {
    if (routes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            Center(child: Padding(padding: EdgeInsets.all(24), child: Text(empty, textAlign: TextAlign.center))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: DriftProTheme.primaryGreen,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
        itemCount: routes.length,
        itemBuilder: (_, i) => PartnerPortalRouteListTile(
          route: routes[i],
          shifts: _data!.shiftsById,
          onReload: _load,
        ),
      ),
    );
  }
}
