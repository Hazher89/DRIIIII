import 'package:flutter/material.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../widgets/partner_route_howto_strip.dart';
import '../widgets/partner_ui.dart';
import 'owner_portal_common.dart';
import 'owner_portal_route_card.dart';

class OwnerPortalRoutesPage extends StatefulWidget {
  final Partner partner;
  const OwnerPortalRoutesPage({super.key, required this.partner});

  @override
  State<OwnerPortalRoutesPage> createState() => _OwnerPortalRoutesPageState();
}

class _OwnerPortalRoutesPageState extends State<OwnerPortalRoutesPage> with SingleTickerProviderStateMixin {
  late TabController _tab;
  OwnerPortalData? _data;
  Map<String, PartnerVehicle> _vehicles = {};
  String? _vehicleFilterId;
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
    final d = await OwnerPortalData.load(widget.partner);
    if (mounted) {
      setState(() {
        _data = d;
        _vehicles = {for (final v in d.vehicles) v.id: v};
        _loading = false;
      });
    }
  }

  List<PartnerRouteShare> _filtered(List<PartnerRouteShare> routes) {
    if (_vehicleFilterId == null) return routes;
    return routes.where((r) => r.partnerVehicleId == _vehicleFilterId).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alle ruter'),
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
                  Tab(text: 'Tidligere (${_data!.routesPast.length})'),
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
                _tabBody(_data!.routesPast, 'Ingen tidligere ruter.'),
              ],
            ),
    );
  }

  Widget _tabBody(List<PartnerRouteShare> routes, String empty) {
    final filtered = _filtered(routes);
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_data!.pendingAckTotal > 0)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: PartnerRouteHowToStrip(compact: true),
              ),
            ),
          SliverToBoxAdapter(child: _vehicleFilters()),
          if (_data!.vehicleStats.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  'Flåte per bil',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: PartnerUi.mutedText(context),
                  ),
                ),
              ),
            ),
          if (_data!.vehicleStats.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: _data!.vehicleStats.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => _compactVehicleTile(_data!.vehicleStats[i]),
                ),
              ),
            ),
          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(empty, textAlign: TextAlign.center),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => OwnerPortalRouteCard(
                    route: filtered[i],
                    vehicle: _vehicles[filtered[i].partnerVehicleId],
                    shifts: _data!.shiftsById,
                    onReload: _load,
                  ),
                  childCount: filtered.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _vehicleFilters() {
    final stats = _data!.vehicleStats;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          FilterChip(
            label: Text('Alle (${_data!.routes.length})'),
            selected: _vehicleFilterId == null,
            onSelected: (_) => setState(() => _vehicleFilterId = null),
          ),
          const SizedBox(width: 6),
          for (final s in stats)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(
                  '${MaviUnitCodes.normalize(s.vehicle.unitCode)}'
                  '${s.pendingAck > 0 ? ' · ${s.pendingAck}' : ''}',
                ),
                selected: _vehicleFilterId == s.vehicle.id,
                onSelected: (_) => setState(() {
                  _vehicleFilterId = _vehicleFilterId == s.vehicle.id ? null : s.vehicle.id;
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _compactVehicleTile(OwnerVehicleStats stats) {
    final unit = MaviUnitCodes.normalize(stats.vehicle.unitCode);
    final util = stats.utilizationPercent.clamp(0, 100);
    final selected = _vehicleFilterId == stats.vehicle.id;
    return Material(
      color: selected
          ? DriftProTheme.primaryGreen.withValues(alpha: 0.12)
          : Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => setState(() {
          _vehicleFilterId = selected ? null : stats.vehicle.id;
        }),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 128,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? DriftProTheme.primaryGreen : Colors.black12,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(unit, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              Text(
                '${util.toStringAsFixed(0)}% · ${stats.routesToday} i dag',
                style: TextStyle(fontSize: 11, color: PartnerUi.mutedText(context)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
