import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/fleet_analytics_service.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/route_load_letters.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';
import '../widgets/partner_portal_route_list_tile.dart';
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
        case OwnerRouteHistorySort.dateAsc:
          if (a.requiresAck && !b2.requiresAck) return -1;
          if (b2.requiresAck && !a.requiresAck) return 1;
          final ta = a.routeStartAt ?? a.shareDate;
          final tb = b2.routeStartAt ?? b2.shareDate;
          return ta.compareTo(tb);
        default:
          if (a.requiresAck && !b2.requiresAck) return -1;
          if (b2.requiresAck && !a.requiresAck) return 1;
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

/// Tidligere ruter — rolig oversikt gruppert per dag.
class OwnerPortalRouteHistoryView extends StatefulWidget {
  const OwnerPortalRouteHistoryView({
    super.key,
    required this.partnerId,
    required this.pastRoutes,
    required this.vehicles,
    required this.shifts,
    this.vehicleFilterId,
    this.onVehicleFilter,
    this.onReload,
    this.onBehalfOfDriver = false,
  });

  final String partnerId;
  final List<PartnerRouteShare> pastRoutes;
  final Map<String, PartnerVehicle> vehicles;
  final Map<String, FleetShiftDefinition> shifts;
  final String? vehicleFilterId;
  final ValueChanged<String?>? onVehicleFilter;
  final Future<void> Function()? onReload;
  final bool onBehalfOfDriver;

  @override
  State<OwnerPortalRouteHistoryView> createState() => _OwnerPortalRouteHistoryViewState();
}

class _OwnerPortalRouteHistoryViewState extends State<OwnerPortalRouteHistoryView> {
  FleetCalendarPeriod _period = FleetCalendarPeriod.month;
  bool _allTime = false;
  DateTime _anchor = DateTime.now();

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

  Future<void> _reload() async {
    await widget.onReload?.call();
  }

  @override
  Widget build(BuildContext context) {
    final routes = sortOwnerHistoryRoutes(
      _filtered,
      OwnerRouteHistorySort.dateDesc,
      widget.vehicles,
    );
    final stats = ownerHistoryStats(routes);
    final buckets = buildOwnerDayBuckets(routes, OwnerRouteHistorySort.dateDesc);
    final muted = PartnerUi.mutedText(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(context, stats, muted, isDark)),
        if (routes.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _emptyState(muted),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _daySection(buckets[i], muted),
                childCount: buckets.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    OwnerRouteHistoryStats stats,
    Color muted,
    bool isDark,
  ) {
    final periodLabel = _allTime
        ? 'Alle tidligere ruter'
        : ownerHistoryPeriodTitle(_period, _anchor);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'week', label: Text('Uke')),
              ButtonSegment(value: 'month', label: Text('Måned')),
              ButtonSegment(value: 'all', label: Text('Alle')),
            ],
            selected: {
              if (_allTime) 'all' else if (_period == FleetCalendarPeriod.week) 'week' else 'month',
            },
            onSelectionChanged: (s) {
              final v = s.first;
              setState(() {
                if (v == 'all') {
                  _allTime = true;
                } else {
                  _allTime = false;
                  _period = v == 'week' ? FleetCalendarPeriod.week : FleetCalendarPeriod.month;
                  _anchor = DateTime.now();
                }
              });
            },
          ),
          if (!_allTime) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton(
                  tooltip: 'Forrige',
                  onPressed: () => _shiftAnchor(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    periodLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                IconButton(
                  tooltip: 'Neste',
                  onPressed: () => _shiftAnchor(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              periodLabel,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: muted),
            ),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : DriftProTheme.primaryGreen.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: DriftProTheme.primaryGreen.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              children: [
                _statCell('${stats.routeCount}', 'ruter'),
                _statDivider(),
                _statCell('${stats.customerCount}', 'kunder'),
                _statDivider(),
                _statCell('${stats.dayCount}', 'dager'),
                if (widget.vehicles.length > 1) ...[
                  _statDivider(),
                  _statCell('${stats.vehicleCount}', 'biler'),
                ],
              ],
            ),
          ),
          if (widget.onVehicleFilter != null && widget.vehicles.length > 1) ...[
            const SizedBox(height: 10),
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
                        label: Text('${MaviUnitCodes.shortLabel(v.unitCode)} ($n)'),
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

  Widget _statCell(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              height: 1.1,
              color: DriftProTheme.primaryGreen,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: PartnerUi.mutedText(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: DriftProTheme.primaryGreen.withValues(alpha: 0.18),
    );
  }

  Widget _emptyState(Color muted) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 44, color: muted.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(
              _allTime
                  ? 'Ingen tidligere ruter ennå'
                  : 'Ingen ruter i denne perioden',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              _allTime
                  ? 'Når ruter er kjørt, dukker de opp her.'
                  : 'Bytt til «Alle» eller bla til en annen uke/måned.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _daySection(OwnerRouteDayBucket b, Color muted) {
    final today = DateTime.now();
    final yesterday = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 1));
    final isYesterday = b.day.year == yesterday.year &&
        b.day.month == yesterday.month &&
        b.day.day == yesterday.day;
    final dayLabel = isYesterday
        ? 'I går · ${DateFormat('d. MMM', 'nb').format(b.day)}'
        : DateFormat('EEEE d. MMMM', 'nb').format(b.day);
    final cust = b.customerCount;
    final loadBadges = RouteLoadLetters.badgesForRoutes(b.routes);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    dayLabel,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                ),
                Text(
                  '${b.routeCount} rute${b.routeCount == 1 ? '' : 'r'}'
                  '${cust > 0 ? ' · $cust kunder' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
          for (final route in b.routes)
            PartnerPortalRouteListTile(
              route: route,
              shifts: widget.shifts,
              onReload: _reload,
              onBehalfOfDriver: widget.onBehalfOfDriver,
              vehicleLabel: _vehicleLabel(route),
              unitCode: widget.vehicles[route.partnerVehicleId]?.unitCode,
              loadBadge: loadBadges[route.id],
            ),
        ],
      ),
    );
  }

  String? _vehicleLabel(PartnerRouteShare route) {
    final vehicle = widget.vehicles[route.partnerVehicleId];
    if (vehicle == null) return null;
    final plate = vehicle.registrationNumber.trim();
    if (plate.isEmpty || plate == '—') {
      return MaviUnitCodes.shortLabel(vehicle.unitCode);
    }
    return '${MaviUnitCodes.shortLabel(vehicle.unitCode)} · $plate';
  }
}
