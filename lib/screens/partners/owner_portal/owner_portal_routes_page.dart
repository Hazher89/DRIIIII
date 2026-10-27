import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/route_load_letters.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../widgets/partner_portal_page_shell.dart';
import '../widgets/partner_ui.dart';
import 'owner_portal_common.dart';
import '../widgets/partner_portal_route_list_tile.dart';
import 'owner_portal_route_history.dart';
import 'owner_portal_routes_focus.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

class OwnerPortalRoutesPage extends StatefulWidget {
  final Partner partner;
  final OwnerPortalRoutesFocus? launchFocus;
  final VoidCallback? onLaunchFocusConsumed;
  final bool staffPortal;

  const OwnerPortalRoutesPage({
    super.key,
    required this.partner,
    this.launchFocus,
    this.onLaunchFocusConsumed,
    this.staffPortal = false,
  });

  @override
  State<OwnerPortalRoutesPage> createState() => _OwnerPortalRoutesPageState();
}

class _OwnerPortalRoutesPageState extends State<OwnerPortalRoutesPage> {
  /// 0 = Kommende, 1 = Tidligere
  int _tab = 0;
  OwnerPortalData? _data;
  Map<String, PartnerVehicle> _vehicles = {};
  String? _vehicleFilterId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OwnerPortalRoutesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.launchFocus != null &&
        widget.launchFocus != oldWidget.launchFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyLaunchFocus());
    }
  }

  void _applyLaunchFocus() {
    final focus = widget.launchFocus;
    if (focus == null || _data == null) return;
    // Legacy: 0/1 = kommende, 2 = tidligere. Nytt: 0 = kommende, 1 = tidligere.
    final tab = focus.tabIndex >= 2 ? 1 : focus.tabIndex.clamp(0, 1);
    setState(() {
      _tab = tab;
      _vehicleFilterId = focus.vehicleId;
    });
    widget.onLaunchFocusConsumed?.call();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() => _loading = true);
    final d = await OwnerPortalData.load(
      widget.partner,
      forceRefresh: forceRefresh,
    );
    if (mounted) {
      setState(() {
        _data = d;
        _vehicles = {for (final v in d.vehicles) v.id: v};
        _loading = false;
      });
      if (widget.launchFocus != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _applyLaunchFocus());
      }
    }
  }

  Future<void> _reload() => _load(forceRefresh: true);

  void _selectVehicle(String vehicleId) {
    setState(() {
      _vehicleFilterId = vehicleId;
      _tab = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pending = _data?.pendingAckTotal ?? 0;
    return PartnerPortalPageShell(
      title: widget.staffPortal ? null : 'Alle ruter',
      showMobileBackButton: !widget.staffPortal,
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
                              '$pending rute(r) venter — trykk for å åpne PDF og akseptere',
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
                        label: Text('Kommende (${_data!.routesKommende.length})'),
                        icon: Icon(
                          pending > 0 ? Icons.mark_email_unread : Icons.route_outlined,
                          size: 18,
                        ),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text('Tidligere (${_data!.routesPast.length})'),
                        icon: const Icon(Icons.history, size: 18),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                ),
                Expanded(
                  child: switch (_tab) {
                    0 => _newRoutesBody(),
                    _ => RefreshIndicator(
                        onRefresh: _reload,
                        child: OwnerPortalRouteHistoryView(
                          partnerId: widget.partner.id,
                          pastRoutes: _data!.routesPast,
                          vehicles: _vehicles,
                          shifts: _data!.shiftsById,
                          vehicleFilterId: _vehicleFilterId,
                          onVehicleFilter: (id) => setState(() => _vehicleFilterId = id),
                          onReload: _reload,
                          onBehalfOfDriver: !widget.staffPortal,
                        ),
                      ),
                  },
                ),
              ],
            ),
    );
  }

  Widget _newRoutesBody() {
    final filtered = _sortedPendingFirst(_filtered(_data!.routesKommende));
    final buckets = buildOwnerDayBuckets(filtered, OwnerRouteHistorySort.dateAsc);
    final muted = PartnerUi.mutedText(context);
    return RefreshIndicator(
      onRefresh: _reload,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (!widget.staffPortal) SliverToBoxAdapter(child: _vehicleFilters()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: Text(
                'Her ligger både nye ruter og aksepterte ruter for i dag og fremover.',
                style: TextStyle(fontSize: 12.5, height: 1.35, color: muted),
              ),
            ),
          ),
          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Ingen kommende ruter. Du får varsel når noe tildeles.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final b = buckets[i];
                    return _kommendeDaySection(b, muted);
                  },
                  childCount: buckets.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kommendeDaySection(OwnerRouteDayBucket b, Color muted) {
    final today = _startOfLocalDay(DateTime.now());
    final day = b.day;
    final String dayLabel;
    if (day == today) {
      dayLabel = 'I dag · ${DateFormat('d. MMM', 'nb').format(day)}';
    } else if (day == today.add(const Duration(days: 1))) {
      dayLabel = 'I morgen · ${DateFormat('d. MMM', 'nb').format(day)}';
    } else {
      dayLabel = DateFormat('EEEE d. MMMM', 'nb').format(day);
    }

    final loadBadges = RouteLoadLetters.badgesForRoutes(b.routes);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
            child: Text(
              dayLabel,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
          ),
          for (final route in b.routes)
            PartnerPortalRouteListTile(
              route: route,
              shifts: _data!.shiftsById,
              onReload: _reload,
              onBehalfOfDriver: !widget.staffPortal,
              vehicleLabel: _vehicleLabel(route),
              unitCode: _vehicles[route.partnerVehicleId]?.unitCode,
              loadBadge: loadBadges[route.id],
            ),
        ],
      ),
    );
  }

  DateTime _startOfLocalDay(DateTime d) => DateTime(d.year, d.month, d.day);

  String? _vehicleLabel(PartnerRouteShare route) {
    final vehicle = _vehicles[route.partnerVehicleId];
    if (vehicle == null) return null;
    final plate = vehicle.registrationNumber.trim();
    if (plate.isEmpty || plate == '—') {
      return MaviUnitCodes.shortLabel(vehicle.unitCode);
    }
    return '${MaviUnitCodes.shortLabel(vehicle.unitCode)} · $plate';
  }

  List<PartnerRouteShare> _filtered(List<PartnerRouteShare> routes) {
    if (_vehicleFilterId == null) return routes;
    return routes.where((r) => r.partnerVehicleId == _vehicleFilterId).toList();
  }

  List<PartnerRouteShare> _sortedPendingFirst(List<PartnerRouteShare> routes) {
    final copy = List<PartnerRouteShare>.from(routes);
    copy.sort((a, b) {
      if (a.requiresAck && !b.requiresAck) return -1;
      if (b.requiresAck && !a.requiresAck) return 1;
      return ownerRouteCalendarDay(a).compareTo(ownerRouteCalendarDay(b));
    });
    return copy;
  }

  Widget _vehicleFilters() {
    final stats = _data!.vehicleStats;
    final newCount = _data!.routesKommende.length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          FilterChip(
            label: Text('Alle ($newCount)'),
            selected: _vehicleFilterId == null,
            onSelected: (_) => setState(() => _vehicleFilterId = null),
          ),
          const SizedBox(width: 6),
          for (final s in stats)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(
                  '${MaviUnitCodes.shortLabel(s.vehicle.unitCode)}'
                  '${s.pendingAck > 0 ? ' · ${s.pendingAck}' : ''}',
                ),
                selected: _vehicleFilterId == s.vehicle.id,
                onSelected: (_) {
                  final vid = s.vehicle.id;
                  if (_vehicleFilterId == vid) {
                    setState(() => _vehicleFilterId = null);
                  } else {
                    _selectVehicle(vid);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

}
