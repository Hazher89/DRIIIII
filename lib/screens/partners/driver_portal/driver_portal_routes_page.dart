import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/user_profile.dart';
import '../widgets/partner_portal_page_shell.dart';
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
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF0F1419) : const Color(0xFFF4F6F8);
    final pending = _data?.pendingAck ?? 0;

    return PartnerPortalPageShell(
      backgroundColor: surface,
      title: 'Mine ruter',
      body: _loading || _data == null
          ? const DriftProLoadingCenter()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pending > 0)
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
                              '$pending nye ruter — trykk på en rute for å åpne, se PDF og akseptere',
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
                      ButtonSegment(
                        value: 0,
                        label: Text('Nye ruter (${_data!.routesNew.length})'),
                        icon: Icon(
                          pending > 0 ? Icons.mark_email_unread : Icons.route_outlined,
                          size: 18,
                        ),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text('Tidligere (${_data!.routesArchive.length})'),
                        icon: const Icon(Icons.history, size: 18),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                ),
                Expanded(
                  child: switch (_tab) {
                    0 => _routeList(
                        _data!.routesNew,
                        'Ingen nye ruter. Du får varsel når noe tildeles.',
                      ),
                    _ => _routeList(
                        _data!.routesArchive,
                        'Ingen tidligere ruter ennå.',
                      ),
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
