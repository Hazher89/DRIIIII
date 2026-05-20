import 'package:flutter/material.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/user_profile.dart';
import 'driver_portal_common.dart';
import 'driver_portal_route_card.dart';

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
    if (mounted) setState(() { _data = d; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF0F1419) : const Color(0xFFF4F6F8);

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
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: SegmentedButton<int>(
                    segments: [
                      ButtonSegment(value: 0, label: Text('I dag (${_data!.routesToday.length})')),
                      ButtonSegment(value: 1, label: Text('Kommende (${_data!.routesUpcoming.length})')),
                      ButtonSegment(value: 2, label: Text('Arkiv (${_data!.routesArchive.length})')),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      _routeList(_data!.routesToday, 'Ingen ruter i dag.'),
                      _routeList(_data!.routesUpcoming, 'Ingen kommende ruter.'),
                      _routeList(_data!.routesArchive, 'Ingen ruter i arkivet.', archive: true),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _routeList(List<PartnerRouteShare> routes, String empty, {bool archive = false}) {
    if (routes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: archive ? 80 : 48),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(empty, textAlign: TextAlign.center),
              ),
            ),
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
        itemBuilder: (_, i) => DriverPortalRouteCard(
          route: routes[i],
          shifts: _data!.shiftsById,
          onReload: _load,
        ),
      ),
    );
  }
}
