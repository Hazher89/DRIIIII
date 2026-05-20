import 'package:flutter/material.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/user_profile.dart';
import '../owner_portal/owner_portal_route_card.dart';
import 'driver_portal_common.dart';

class DriverPortalRoutesPage extends StatefulWidget {
  final Partner partner;
  final UserProfile profile;

  const DriverPortalRoutesPage({super.key, required this.partner, required this.profile});

  @override
  State<DriverPortalRoutesPage> createState() => _DriverPortalRoutesPageState();
}

class _DriverPortalRoutesPageState extends State<DriverPortalRoutesPage> with SingleTickerProviderStateMixin {
  late TabController _tab;
  DriverPortalData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mine ruter'),
        actions: [
          IconButton(tooltip: 'Oppdater', onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            tooltip: 'Logg ut',
            icon: const Icon(Icons.logout),
            onPressed: () => signOutFromPortal(context),
          ),
        ],
        bottom: _data == null
            ? null
            : TabBar(
                controller: _tab,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'I dag (${_data!.routesToday.length})'),
                  Tab(text: 'Kommende (${_data!.routesUpcoming.length})'),
                  Tab(text: 'Arkiv (${_data!.routesArchive.length})'),
                ],
              ),
      ),
      body: _loading || _data == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _tabBody(_data!.routesToday, 'Ingen ruter i dag.'),
                _tabBody(_data!.routesUpcoming, 'Ingen kommende ruter.'),
                _tabBody(_data!.routesArchive, 'Ingen ruter i arkivet ennå.', archive: true),
              ],
            ),
    );
  }

  Widget _tabBody(List<PartnerRouteShare> routes, String empty, {bool archive = false}) {
    return RefreshIndicator(
      onRefresh: _load,
      child: routes.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: archive ? 80 : 48),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      empty,
                      textAlign: TextAlign.center,
                      style: const TextStyle(height: 1.4),
                    ),
                  ),
                ),
                if (archive)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Tidligere ruter beholder PDF i arkivet — trykk «Åpne rute-PDF».',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: routes.length,
              itemBuilder: (_, i) {
                final r = routes[i];
                return OwnerPortalRouteCard(
                  route: r,
                  vehicle: _data!.vehicle,
                  shifts: _data!.shiftsById,
                  onReload: _load,
                  onBehalfOfDriver: false,
                );
              },
            ),
    );
  }
}
