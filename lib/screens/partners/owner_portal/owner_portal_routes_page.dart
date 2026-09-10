import 'package:flutter/material.dart';

import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/theme/app_theme.dart';
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
  /// 0 = Nye ruter (trenger aksept), 1 = Tidligere
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
    // Legacy: 0/1 = nye, 2 = tidligere. Nytt: 0 = nye, 1 = tidligere.
    final tab = focus.tabIndex >= 2 ? 1 : focus.tabIndex.clamp(0, 1);
    setState(() {
      _tab = tab;
      _vehicleFilterId = focus.vehicleId;
    });
    widget.onLaunchFocusConsumed?.call();
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
      if (widget.launchFocus != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _applyLaunchFocus());
      }
    }
  }

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
                        label: Text('Nye ruter (${_data!.routesNew.length})'),
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
                        onRefresh: _load,
                        child: OwnerPortalRouteHistoryView(
                          partnerId: widget.partner.id,
                          pastRoutes: _data!.routesPast,
                          vehicles: _vehicles,
                          shifts: _data!.shiftsById,
                          vehicleFilterId: _vehicleFilterId,
                          onVehicleFilter: (id) => setState(() => _vehicleFilterId = id),
                        ),
                      ),
                  },
                ),
              ],
            ),
    );
  }

  Widget _newRoutesBody() {
    final filtered = _sortedPendingFirst(_filtered(_data!.routesNew));
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (!widget.staffPortal) SliverToBoxAdapter(child: _vehicleFilters()),
          if (!widget.staffPortal && _data!.vehicleStats.isNotEmpty)
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
          if (!widget.staffPortal && _data!.vehicleStats.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 84,
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
                  child: Text(
                    'Ingen nye ruter. Du får varsel når noe tildeles.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: PartnerUi.mutedText(context)),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final route = filtered[i];
                    final vehicle = _vehicles[route.partnerVehicleId];
                    final vehicleLabel = vehicle != null
                        ? '${MaviUnitCodes.normalize(vehicle.unitCode)} · ${vehicle.registrationNumber}'
                        : null;
                    return PartnerPortalRouteListTile(
                      route: route,
                      shifts: _data!.shiftsById,
                      onReload: _load,
                      onBehalfOfDriver: !widget.staffPortal,
                      vehicleLabel: vehicleLabel,
                    );
                  },
                  childCount: filtered.length,
                ),
              ),
            ),
        ],
      ),
    );
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
    final newCount = _data!.routesNew.length;
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
                  '${MaviUnitCodes.normalize(s.vehicle.unitCode)}'
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

  Widget _compactVehicleTile(OwnerVehicleStats stats) {
    final unit = MaviUnitCodes.normalize(stats.vehicle.unitCode);
    final util = stats.utilizationPercent.clamp(0, 100);
    final selected = _vehicleFilterId == stats.vehicle.id;
    final pending = stats.pendingAck;
    return Material(
      color: selected
          ? DriftProTheme.primaryGreen.withValues(alpha: 0.12)
          : Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (selected) {
            setState(() => _vehicleFilterId = null);
          } else {
            _selectVehicle(stats.vehicle.id);
          }
        },
        child: Container(
          width: 132,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? DriftProTheme.primaryGreen
                  : pending > 0
                      ? Colors.orange.shade300
                      : Colors.black12,
              width: selected || pending > 0 ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                unit,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                pending > 0
                    ? '$pending venter · ${util.toStringAsFixed(0)}%'
                    : '${util.toStringAsFixed(0)}% utnyttelse',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: pending > 0
                      ? Colors.orange.shade800
                      : PartnerUi.mutedText(context),
                ),
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
