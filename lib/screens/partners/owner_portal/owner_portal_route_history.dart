import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/fleet_analytics_service.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';
import '../widgets/partner_route_pdf_actions.dart';
import '../widgets/partner_ui.dart';
import 'owner_portal_common.dart';

enum OwnerRouteHistoryGroup { byDay, byVehicle, flat }

extension OwnerRouteHistoryGroupX on OwnerRouteHistoryGroup {
  String get label {
    switch (this) {
      case OwnerRouteHistoryGroup.byDay:
        return 'Per dag';
      case OwnerRouteHistoryGroup.byVehicle:
        return 'Per bil';
      case OwnerRouteHistoryGroup.flat:
        return 'Alle ruter';
    }
  }
}

enum OwnerRouteHistorySort {
  dateDesc,
  dateAsc,
  customersDesc,
  customersAsc,
  vehicleAsc,
}

extension OwnerRouteHistorySortX on OwnerRouteHistorySort {
  String get label {
    switch (this) {
      case OwnerRouteHistorySort.dateDesc:
        return 'Nyeste først';
      case OwnerRouteHistorySort.dateAsc:
        return 'Eldste først';
      case OwnerRouteHistorySort.customersDesc:
        return 'Flest kunder';
      case OwnerRouteHistorySort.customersAsc:
        return 'Færrest kunder';
      case OwnerRouteHistorySort.vehicleAsc:
        return 'Bil A–Å';
    }
  }
}

int ownerRouteCustomerCount(PartnerRouteShare r) => r.customerCount ?? 0;

class OwnerRouteDayBucket {
  const OwnerRouteDayBucket({required this.day, required this.routes});

  final DateTime day;
  final List<PartnerRouteShare> routes;

  int get routeCount => routes.length;
  int get customerCount =>
      routes.fold<int>(0, (s, r) => s + ownerRouteCustomerCount(r));
}

class OwnerRouteVehicleBucket {
  const OwnerRouteVehicleBucket({
    required this.vehicleId,
    required this.unitLabel,
    required this.routes,
  });

  final String vehicleId;
  final String unitLabel;
  final List<PartnerRouteShare> routes;

  int get routeCount => routes.length;
  int get customerCount =>
      routes.fold<int>(0, (s, r) => s + ownerRouteCustomerCount(r));

  Set<DateTime> get days =>
      routes.map(ownerRouteCalendarDay).toSet();
}

class OwnerRouteHistoryStats {
  const OwnerRouteHistoryStats({
    required this.routeCount,
    required this.customerCount,
    required this.dayCount,
    required this.vehicleCount,
  });

  final int routeCount;
  final int customerCount;
  final int dayCount;
  final int vehicleCount;
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

(DateTime, DateTime) ownerHistoryPeriodRange(FleetCalendarPeriod period, DateTime anchor) {
  final a = _dayOnly(anchor);
  switch (period) {
    case FleetCalendarPeriod.day:
      return (a, a);
    case FleetCalendarPeriod.week:
      final start = a.subtract(Duration(days: a.weekday - DateTime.monday));
      return (start, start.add(const Duration(days: 6)));
    case FleetCalendarPeriod.month:
      final start = DateTime(a.year, a.month, 1);
      final end = DateTime(a.year, a.month + 1, 0);
      return (start, end);
    case FleetCalendarPeriod.year:
      return (DateTime(a.year, 1, 1), DateTime(a.year, 12, 31));
  }
}

String ownerHistoryPeriodTitle(FleetCalendarPeriod period, DateTime anchor) {
  final (from, to) = ownerHistoryPeriodRange(period, anchor);
  switch (period) {
    case FleetCalendarPeriod.day:
      return DateFormat('EEEE d. MMMM yyyy', 'nb').format(from);
    case FleetCalendarPeriod.week:
      return '${DateFormat('d. MMM', 'nb').format(from)} – ${DateFormat('d. MMM yyyy', 'nb').format(to)}';
    case FleetCalendarPeriod.month:
      return DateFormat('MMMM yyyy', 'nb').format(from);
    case FleetCalendarPeriod.year:
      return '${from.year}';
  }
}

List<PartnerRouteShare> filterOwnerHistoryRoutes({
  required String partnerId,
  required List<PartnerRouteShare> pastRoutes,
  required FleetCalendarPeriod period,
  required DateTime anchor,
  String? vehicleId,
  bool allTime = false,
}) {
  var list = pastRoutes
      .where((r) => r.partnerId == partnerId)
      .where((r) => r.pdfStoragePath.trim().isNotEmpty || r.isSentWithNotify)
      .toList();
  if (vehicleId != null) {
    list = list.where((r) => r.partnerVehicleId == vehicleId).toList();
  }
  if (!allTime) {
    final (from, to) = ownerHistoryPeriodRange(period, anchor);
    list = list.where((r) {
      final d = ownerRouteCalendarDay(r);
      return !d.isBefore(from) && !d.isAfter(to);
    }).toList();
  }
  return list;
}

OwnerRouteHistoryStats ownerHistoryStats(List<PartnerRouteShare> routes) {
  final days = routes.map(ownerRouteCalendarDay).toSet();
  final vehicles = routes.map((r) => r.partnerVehicleId).whereType<String>().toSet();
  return OwnerRouteHistoryStats(
    routeCount: routes.length,
    customerCount: routes.fold<int>(0, (s, r) => s + ownerRouteCustomerCount(r)),
    dayCount: days.length,
    vehicleCount: vehicles.length,
  );
}

List<PartnerRouteShare> sortOwnerHistoryRoutes(
  List<PartnerRouteShare> routes,
  OwnerRouteHistorySort sort,
  Map<String, PartnerVehicle> vehicles,
) {
  final copy = List<PartnerRouteShare>.from(routes);
  int cmpDay(PartnerRouteShare a, PartnerRouteShare b) =>
      ownerRouteCalendarDay(a).compareTo(ownerRouteCalendarDay(b));

  String unit(PartnerRouteShare r) {
    final v = vehicles[r.partnerVehicleId];
    return v != null ? MaviUnitCodes.normalize(v.unitCode) : '—';
  }

  switch (sort) {
    case OwnerRouteHistorySort.dateDesc:
      copy.sort((a, b) => cmpDay(b, a));
      break;
    case OwnerRouteHistorySort.dateAsc:
      copy.sort(cmpDay);
      break;
    case OwnerRouteHistorySort.customersDesc:
      copy.sort((a, b) {
        final c = ownerRouteCustomerCount(b).compareTo(ownerRouteCustomerCount(a));
        return c != 0 ? c : cmpDay(b, a);
      });
      break;
    case OwnerRouteHistorySort.customersAsc:
      copy.sort((a, b) {
        final c = ownerRouteCustomerCount(a).compareTo(ownerRouteCustomerCount(b));
        return c != 0 ? c : cmpDay(b, a);
      });
      break;
    case OwnerRouteHistorySort.vehicleAsc:
      copy.sort((a, b) {
        final u = unit(a).compareTo(unit(b));
        return u != 0 ? u : cmpDay(b, a);
      });
      break;
  }
  return copy;
}

List<OwnerRouteDayBucket> buildOwnerDayBuckets(
  List<PartnerRouteShare> routes,
  OwnerRouteHistorySort sort,
) {
  final byDay = <DateTime, List<PartnerRouteShare>>{};
  for (final r in routes) {
    final d = ownerRouteCalendarDay(r);
    byDay.putIfAbsent(d, () => []).add(r);
  }
  final buckets = byDay.entries
      .map((e) => OwnerRouteDayBucket(day: e.key, routes: e.value))
      .toList();
  buckets.sort((a, b) => b.day.compareTo(a.day));
  for (final b in buckets) {
    b.routes.sort((a, b2) {
      switch (sort) {
        case OwnerRouteHistorySort.customersDesc:
          return ownerRouteCustomerCount(b2).compareTo(ownerRouteCustomerCount(a));
        case OwnerRouteHistorySort.customersAsc:
          return ownerRouteCustomerCount(a).compareTo(ownerRouteCustomerCount(b2));
        default:
          final ta = a.routeStartAt ?? a.shareDate;
          final tb = b2.routeStartAt ?? b2.shareDate;
          return tb.compareTo(ta);
      }
    });
  }
  if (sort == OwnerRouteHistorySort.dateAsc) {
    buckets.sort((a, b) => a.day.compareTo(b.day));
  } else if (sort == OwnerRouteHistorySort.customersDesc) {
    buckets.sort((a, b) => b.customerCount.compareTo(a.customerCount));
  } else if (sort == OwnerRouteHistorySort.customersAsc) {
    buckets.sort((a, b) => a.customerCount.compareTo(b.customerCount));
  }
  return buckets;
}

List<OwnerRouteVehicleBucket> buildOwnerVehicleBuckets(
  List<PartnerRouteShare> routes,
  Map<String, PartnerVehicle> vehicles,
  OwnerRouteHistorySort sort,
) {
  final byVid = <String, List<PartnerRouteShare>>{};
  for (final r in routes) {
    final vid = r.partnerVehicleId;
    if (vid == null) continue;
    byVid.putIfAbsent(vid, () => []).add(r);
  }
  final buckets = <OwnerRouteVehicleBucket>[];
  for (final e in byVid.entries) {
    final v = vehicles[e.key];
    buckets.add(
      OwnerRouteVehicleBucket(
        vehicleId: e.key,
        unitLabel: v != null ? MaviUnitCodes.normalize(v.unitCode) : '—',
        routes: e.value,
      ),
    );
  }
  switch (sort) {
    case OwnerRouteHistorySort.vehicleAsc:
      buckets.sort((a, b) => a.unitLabel.compareTo(b.unitLabel));
      break;
    case OwnerRouteHistorySort.customersAsc:
      buckets.sort((a, b) => a.customerCount.compareTo(b.customerCount));
      break;
    case OwnerRouteHistorySort.customersDesc:
    case OwnerRouteHistorySort.dateDesc:
      buckets.sort((a, b) => b.customerCount.compareTo(a.customerCount));
      break;
    case OwnerRouteHistorySort.dateAsc:
      buckets.sort((a, b) => a.unitLabel.compareTo(b.unitLabel));
      break;
  }
  return buckets;
}

/// Tidligere ruter — full oversikt med PDF, kunder, periode og sortering.
class OwnerPortalRouteHistoryView extends StatefulWidget {
  const OwnerPortalRouteHistoryView({
    super.key,
    required this.partnerId,
    required this.pastRoutes,
    required this.vehicles,
    required this.shifts,
    this.vehicleFilterId,
    this.onVehicleFilter,
  });

  final String partnerId;
  final List<PartnerRouteShare> pastRoutes;
  final Map<String, PartnerVehicle> vehicles;
  final Map<String, FleetShiftDefinition> shifts;
  final String? vehicleFilterId;
  final ValueChanged<String?>? onVehicleFilter;

  @override
  State<OwnerPortalRouteHistoryView> createState() => _OwnerPortalRouteHistoryViewState();
}

class _OwnerPortalRouteHistoryViewState extends State<OwnerPortalRouteHistoryView> {
  FleetCalendarPeriod _period = FleetCalendarPeriod.month;
  bool _allTime = false;
  DateTime _anchor = DateTime.now();
  OwnerRouteHistoryGroup _group = OwnerRouteHistoryGroup.byDay;
  OwnerRouteHistorySort _sort = OwnerRouteHistorySort.dateDesc;

  List<PartnerRouteShare> get _filtered => filterOwnerHistoryRoutes(
        partnerId: widget.partnerId,
        pastRoutes: widget.pastRoutes,
        period: _period,
        anchor: _anchor,
        vehicleId: widget.vehicleFilterId,
        allTime: _allTime,
      );

  void _shiftAnchor(int delta) {
    setState(() {
      switch (_period) {
        case FleetCalendarPeriod.day:
          _anchor = _anchor.add(Duration(days: delta));
          break;
        case FleetCalendarPeriod.week:
          _anchor = _anchor.add(Duration(days: 7 * delta));
          break;
        case FleetCalendarPeriod.month:
          _anchor = DateTime(_anchor.year, _anchor.month + delta, 1);
          break;
        case FleetCalendarPeriod.year:
          _anchor = DateTime(_anchor.year + delta, _anchor.month, _anchor.day);
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final routes = sortOwnerHistoryRoutes(_filtered, _sort, widget.vehicles);
    final stats = ownerHistoryStats(routes);
    final multiVehicle = widget.vehicles.length > 1;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(context, stats)),
        if (multiVehicle) SliverToBoxAdapter(child: _vehicleOverview(routes)),
        if (routes.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _allTime
                      ? 'Ingen tidligere ruter registrert ennå.'
                      : 'Ingen ruter i valgt periode.\nPrøv «Alle» eller bla til en annen uke/måned.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: PartnerUi.mutedText(context), height: 1.4),
                ),
              ),
            ),
          )
        else
          switch (_group) {
            OwnerRouteHistoryGroup.byDay => _daySlivers(routes),
            OwnerRouteHistoryGroup.byVehicle => _vehicleSlivers(routes),
            OwnerRouteHistoryGroup.flat => _flatSlivers(routes),
          },
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, OwnerRouteHistoryStats stats) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tidligere ruter · ${widget.vehicles.length <= 1 ? 'din bedrift' : 'dine biler'}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: PartnerUi.mutedText(context),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _kpi(Icons.route_outlined, '${stats.routeCount}', 'Ruter'),
              _kpi(Icons.people_outline, '${stats.customerCount}', 'Kunder'),
              _kpi(Icons.calendar_today_outlined, '${stats.dayCount}', 'Dager'),
              if (widget.vehicles.length > 1)
                _kpi(Icons.local_shipping_outlined, '${stats.vehicleCount}', 'Biler'),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Alle'),
                  selected: _allTime,
                  onSelected: (_) => setState(() => _allTime = true),
                ),
                const SizedBox(width: 6),
                ...FleetCalendarPeriod.values.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(p.label),
                      selected: !_allTime && _period == p,
                      onSelected: (_) => setState(() {
                        _allTime = false;
                        _period = p;
                        _anchor = DateTime.now();
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_allTime) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: 'Forrige',
                  onPressed: () => _shiftAnchor(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    ownerHistoryPeriodTitle(_period, _anchor),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
                IconButton(
                  tooltip: 'Neste',
                  onPressed: () => _shiftAnchor(1),
                  icon: const Icon(Icons.chevron_right),
                ),
                TextButton(
                  onPressed: () => setState(() => _anchor = DateTime.now()),
                  child: const Text('I dag'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...OwnerRouteHistoryGroup.values.map(
                  (g) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(g.label),
                      selected: _group == g,
                      onSelected: (_) => setState(() => _group = g),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                PopupMenuButton<OwnerRouteHistorySort>(
                  tooltip: 'Sortering',
                  initialValue: _sort,
                  onSelected: (s) => setState(() => _sort = s),
                  child: Chip(
                    avatar: const Icon(Icons.sort, size: 18),
                    label: Text(_sort.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  itemBuilder: (_) => OwnerRouteHistorySort.values
                      .map(
                        (s) => PopupMenuItem(
                          value: s,
                          child: Text(s.label),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          if (widget.onVehicleFilter != null && widget.vehicles.length > 1) ...[
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: Text('Alle biler (${widget.pastRoutes.length})'),
                    selected: widget.vehicleFilterId == null,
                    onSelected: (_) => widget.onVehicleFilter!(null),
                  ),
                  const SizedBox(width: 6),
                  ...widget.vehicles.values.map((v) {
                    final id = v.id;
                    final n = widget.pastRoutes.where((r) => r.partnerVehicleId == id).length;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text('${MaviUnitCodes.normalize(v.unitCode)} ($n)'),
                        selected: widget.vehicleFilterId == id,
                        onSelected: (_) => widget.onVehicleFilter!(
                          widget.vehicleFilterId == id ? null : id,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kpi(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: DriftProTheme.primaryGreen),
          const SizedBox(width: 5),
          Text(
            '$value $label',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _vehicleOverview(List<PartnerRouteShare> routes) {
    final buckets = buildOwnerVehicleBuckets(routes, widget.vehicles, OwnerRouteHistorySort.customersDesc);
    if (buckets.length < 2) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Oversikt per bil (valgt periode)',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: PartnerUi.mutedText(context),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: buckets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final b = buckets[i];
                return _vehicleSummaryCard(b);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _vehicleSummaryCard(OwnerRouteVehicleBucket b) {
    return Container(
      width: 108,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(b.unitLabel, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
          Text(
            '${b.routeCount} r · ${b.customerCount} knd',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  SliverList _daySlivers(List<PartnerRouteShare> routes) {
    final buckets = buildOwnerDayBuckets(routes, _sort);
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final b = buckets[i];
          return _dayExpansion(b);
        },
        childCount: buckets.length,
      ),
    );
  }

  Widget _dayExpansion(OwnerRouteDayBucket b) {
    final dayLabel = DateFormat('EEE d. MMM yyyy', 'nb').format(b.day);
    final recent = b.day.isAfter(DateTime.now().subtract(const Duration(days: 7)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          initiallyExpanded: recent,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          childrenPadding: EdgeInsets.zero,
          title: Text(
            dayLabel,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          subtitle: Text(
            '${b.routeCount} r · ${b.customerCount} knd',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
          ),
          children: [
            for (var i = 0; i < b.routes.length; i++) ...[
              if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
              _routeTile(b.routes[i]),
            ],
          ],
        ),
      ),
    );
  }

  SliverList _vehicleSlivers(List<PartnerRouteShare> routes) {
    final buckets = buildOwnerVehicleBuckets(routes, widget.vehicles, _sort);
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final b = buckets[i];
          final dayBuckets = buildOwnerDayBuckets(b.routes, OwnerRouteHistorySort.dateDesc);
          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
            child: Material(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  b.unitLabel,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                subtitle: Text(
                  '${b.routeCount} r · ${b.customerCount} knd · ${b.days.length} d',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
                children: [
                  for (final db in dayBuckets) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
                      child: Text(
                        DateFormat('d. MMM yyyy', 'nb').format(db.day),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                      ),
                    ),
                    for (var i = 0; i < db.routes.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
                      _routeTile(db.routes[i]),
                    ],
                  ],
                ],
              ),
            ),
          );
        },
        childCount: buckets.length,
      ),
    );
  }

  Widget _flatSlivers(List<PartnerRouteShare> routes) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => Column(
            children: [
              if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
              _routeTile(routes[i]),
            ],
          ),
          childCount: routes.length,
        ),
      ),
    );
  }

  Widget _routeTile(PartnerRouteShare route) {
    final vehicle = widget.vehicles[route.partnerVehicleId];
    final unit = vehicle != null ? MaviUnitCodes.normalize(vehicle.unitCode) : null;
    final customers = ownerRouteCustomerCount(route);
    final hasPdf = route.pdfStoragePath.trim().isNotEmpty;
    final day = ownerRouteCalendarDay(route);
    final time = route.routeStartAt != null
        ? DateFormat('HH:mm', 'nb').format(route.routeStartAt!.toLocal())
        : null;
    final area = ownerRouteArea(route, widget.shifts);
    final title = route.title ?? area;
    final custLabel = customers > 0
        ? '$customers knd'
        : (route.customerCount == null ? '— knd' : '0 knd');

    return InkWell(
      onTap: hasPdf ? () => PartnerRoutePdfActions.openPdf(context, route) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          children: [
            PartnerRoutePdfActions.ackDot(route, size: 8),
            const SizedBox(width: 8),
            if (unit != null) ...[
              Text(
                unit,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: DriftProTheme.primaryGreen,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    [
                      if (_group == OwnerRouteHistoryGroup.byDay) ...[
                        if (time != null) time,
                      ] else ...[
                        DateFormat('d. MMM', 'nb').format(day),
                        if (time != null) time,
                      ],
                      custLabel,
                    ].join(' · '),
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'PDF',
              onPressed: hasPdf ? () => PartnerRoutePdfActions.openPdf(context, route) : null,
              icon: Icon(
                Icons.picture_as_pdf_outlined,
                size: 18,
                color: hasPdf ? DriftProTheme.primaryGreen : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
