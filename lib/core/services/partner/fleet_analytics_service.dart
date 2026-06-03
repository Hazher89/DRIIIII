import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/mavi_driver_day_assignment.dart';
import '../../../models/partner/partner_links.dart';
import 'mavi_unit_codes.dart';
import 'partner_service.dart';
import 'route_pdf_text_service.dart';

enum FleetStatsPeriod { days7, days30, days90, year, all }

/// Kalenderperioder for sjåfør-/rute-statistikk (dag, uke, måned, år).
enum FleetCalendarPeriod { day, week, month, year }

extension FleetCalendarPeriodX on FleetCalendarPeriod {
  String get label {
    switch (this) {
      case FleetCalendarPeriod.day:
        return 'Dag';
      case FleetCalendarPeriod.week:
        return 'Uke';
      case FleetCalendarPeriod.month:
        return 'Måned';
      case FleetCalendarPeriod.year:
        return 'År';
    }
  }

  DateTime rangeStart(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case FleetCalendarPeriod.day:
        return today;
      case FleetCalendarPeriod.week:
        return today.subtract(Duration(days: today.weekday - 1));
      case FleetCalendarPeriod.month:
        return DateTime(now.year, now.month, 1);
      case FleetCalendarPeriod.year:
        return DateTime(now.year, 1, 1);
    }
  }

  String periodDescription(DateTime now) {
    final start = rangeStart(now);
    switch (this) {
      case FleetCalendarPeriod.day:
        return _nbDate(start);
      case FleetCalendarPeriod.week:
        return '${_nbDate(start)} – ${_nbDate(now)}';
      case FleetCalendarPeriod.month:
        return '${start.month}. ${_monthName(start.month)} ${start.year}';
      case FleetCalendarPeriod.year:
        return '${start.year}';
    }
  }

  static String _nbDate(DateTime d) => '${d.day}. ${d.month}. ${d.year}';

  static String _monthName(int m) {
    const names = [
      '', 'januar', 'februar', 'mars', 'april', 'mai', 'juni',
      'juli', 'august', 'september', 'oktober', 'november', 'desember',
    ];
    return names[m];
  }
}

class FleetDriverStat {
  final String vehicleId;
  final String? driverName;
  final String maviLabel;
  final String partnerName;
  final int routeCount;
  final int customerCount;
  final int friDays;
  final double routeVsAvg;
  final double customerVsAvg;
  final Map<String, int> routesByRegion;
  final Map<String, int> customersByRegion;

  const FleetDriverStat({
    required this.vehicleId,
    this.driverName,
    required this.maviLabel,
    required this.partnerName,
    required this.routeCount,
    required this.customerCount,
    required this.friDays,
    this.routeVsAvg = 0,
    this.customerVsAvg = 0,
    this.routesByRegion = const {},
    this.customersByRegion = const {},
  });

  /// Primær identitet i statistikk — alltid MAVI-nummer.
  String get displayMavi {
    final n = MaviUnitCodes.normalize(maviLabel);
    return n.isNotEmpty ? n : maviLabel;
  }

  String? get displayDriver {
    final d = driverName?.trim();
    if (d == null || d.isEmpty) return null;
    return d;
  }

  double get customersPerRoute => routeCount > 0 ? customerCount / routeCount : 0;

  String? get topRegion {
    if (routesByRegion.isEmpty) return null;
    return routesByRegion.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  int get regionCount => routesByRegion.length;

  String get description =>
      '$routeCount ${routeCount == 1 ? 'rute' : 'ruter'} · $customerCount ${customerCount == 1 ? 'kunde' : 'kunder'}'
      '${friDays > 0 ? ' · $friDays fri' : ''}';
}

enum FleetDriverSortKey {
  routesDesc,
  routesAsc,
  customersDesc,
  customersAsc,
  customersPerRouteDesc,
  customersPerRouteAsc,
  friDesc,
  maviAsc,
  driverAsc,
  partnerAsc,
  fairnessDesc,
  fairnessAsc,
  customerFairnessDesc,
  customerFairnessAsc,
  topRegionAsc,
  regionSpreadDesc,
}

extension FleetDriverSortKeyX on FleetDriverSortKey {
  String get label {
    switch (this) {
      case FleetDriverSortKey.routesDesc:
        return 'Flest ruter';
      case FleetDriverSortKey.routesAsc:
        return 'Færrest ruter';
      case FleetDriverSortKey.customersDesc:
        return 'Flest kunder';
      case FleetDriverSortKey.customersAsc:
        return 'Færrest kunder';
      case FleetDriverSortKey.friDesc:
        return 'Mest fri';
      case FleetDriverSortKey.maviAsc:
        return 'MAVI A–Å';
      case FleetDriverSortKey.fairnessDesc:
        return 'Over snitt (ruter)';
      case FleetDriverSortKey.fairnessAsc:
        return 'Under snitt (ruter)';
      case FleetDriverSortKey.customersPerRouteDesc:
        return 'Flest knd/rute';
      case FleetDriverSortKey.customersPerRouteAsc:
        return 'Færrest knd/rute';
      case FleetDriverSortKey.driverAsc:
        return 'Sjåfør A–Å';
      case FleetDriverSortKey.partnerAsc:
        return 'Partner A–Å';
      case FleetDriverSortKey.customerFairnessDesc:
        return 'Over snitt (kunder)';
      case FleetDriverSortKey.customerFairnessAsc:
        return 'Under snitt (kunder)';
      case FleetDriverSortKey.topRegionAsc:
        return 'Område A–Å';
      case FleetDriverSortKey.regionSpreadDesc:
        return 'Flest områder';
    }
  }
}

class FleetRegionStat {
  final String region;
  final int routeCount;
  final int customerCount;
  final int driverCount;
  final String? topDriverMavi;
  final String? topDriverName;
  final int topDriverRoutes;

  const FleetRegionStat({
    required this.region,
    required this.routeCount,
    required this.customerCount,
    required this.driverCount,
    this.topDriverMavi,
    this.topDriverName,
    this.topDriverRoutes = 0,
  });
}

enum FleetRegionSortKey {
  routesDesc,
  routesAsc,
  customersDesc,
  customersAsc,
  regionAsc,
  driversDesc,
}

extension FleetRegionSortKeyX on FleetRegionSortKey {
  String get label {
    switch (this) {
      case FleetRegionSortKey.routesDesc:
        return 'Flest ruter';
      case FleetRegionSortKey.routesAsc:
        return 'Færrest ruter';
      case FleetRegionSortKey.customersDesc:
        return 'Flest kunder';
      case FleetRegionSortKey.customersAsc:
        return 'Færrest kunder';
      case FleetRegionSortKey.regionAsc:
        return 'Område A–Å';
      case FleetRegionSortKey.driversDesc:
        return 'Flest sjåfører';
    }
  }
}

enum FleetDriverFilterKey { all, withRoutes, withCustomers, friOnly, onlyActiveMavi }

extension FleetDriverFilterKeyX on FleetDriverFilterKey {
  String get label {
    switch (this) {
      case FleetDriverFilterKey.all:
        return 'Alle MAVI';
      case FleetDriverFilterKey.withRoutes:
        return 'Har fått rute';
      case FleetDriverFilterKey.withCustomers:
        return 'Har kunder';
      case FleetDriverFilterKey.friOnly:
        return 'Kun fri';
      case FleetDriverFilterKey.onlyActiveMavi:
        return 'Aktive i flåte';
    }
  }
}

class FleetDriverStatsBundle {
  final FleetCalendarPeriod period;
  final List<FleetDriverStat> drivers;
  final List<FleetRegionStat> regions;
  final int totalRoutes;
  final int totalCustomers;
  final int activeMaviCount;
  final double avgRoutesPerMavi;
  final double avgCustomersPerMavi;
  final FleetDriverStat? mostRoutes;
  final FleetDriverStat? leastRoutes;
  final FleetDriverStat? mostCustomers;
  final FleetDriverStat? leastCustomers;
  final FleetDriverStat? mostFri;
  final FleetRegionStat? mostActiveRegion;

  const FleetDriverStatsBundle({
    required this.period,
    required this.drivers,
    this.regions = const [],
    required this.totalRoutes,
    required this.totalCustomers,
    required this.activeMaviCount,
    required this.avgRoutesPerMavi,
    required this.avgCustomersPerMavi,
    this.mostRoutes,
    this.leastRoutes,
    this.mostCustomers,
    this.leastCustomers,
    this.mostFri,
    this.mostActiveRegion,
  });

  List<FleetDriverStat> filtered({
    FleetDriverFilterKey filter = FleetDriverFilterKey.all,
    String? partnerName,
    String maviQuery = '',
    Set<String>? activeVehicleIds,
  }) {
    final q = maviQuery.trim().toLowerCase();
    return drivers.where((d) {
      if (partnerName != null && partnerName.isNotEmpty && d.partnerName != partnerName) {
        return false;
      }
      if (q.isNotEmpty &&
          !d.displayMavi.toLowerCase().contains(q) &&
          !(d.displayDriver?.toLowerCase().contains(q) ?? false) &&
          !d.partnerName.toLowerCase().contains(q)) {
        return false;
      }
      switch (filter) {
        case FleetDriverFilterKey.withRoutes:
          return d.routeCount > 0;
        case FleetDriverFilterKey.withCustomers:
          return d.customerCount > 0;
        case FleetDriverFilterKey.friOnly:
          return d.friDays > 0 && d.routeCount == 0;
        case FleetDriverFilterKey.onlyActiveMavi:
          return activeVehicleIds == null || activeVehicleIds.contains(d.vehicleId);
        case FleetDriverFilterKey.all:
          return d.routeCount > 0 || d.customerCount > 0 || d.friDays > 0;
      }
    }).toList();
  }

  static List<FleetDriverStat> sorted(List<FleetDriverStat> list, FleetDriverSortKey key) {
    final copy = [...list];
    switch (key) {
      case FleetDriverSortKey.routesDesc:
        copy.sort((a, b) => b.routeCount.compareTo(a.routeCount));
        break;
      case FleetDriverSortKey.routesAsc:
        copy.sort((a, b) => a.routeCount.compareTo(b.routeCount));
        break;
      case FleetDriverSortKey.customersDesc:
        copy.sort((a, b) => b.customerCount.compareTo(a.customerCount));
        break;
      case FleetDriverSortKey.customersAsc:
        copy.sort((a, b) => a.customerCount.compareTo(b.customerCount));
        break;
      case FleetDriverSortKey.friDesc:
        copy.sort((a, b) => b.friDays.compareTo(a.friDays));
        break;
      case FleetDriverSortKey.maviAsc:
        copy.sort((a, b) => a.displayMavi.compareTo(b.displayMavi));
        break;
      case FleetDriverSortKey.fairnessDesc:
        copy.sort((a, b) => b.routeVsAvg.compareTo(a.routeVsAvg));
        break;
      case FleetDriverSortKey.fairnessAsc:
        copy.sort((a, b) => a.routeVsAvg.compareTo(b.routeVsAvg));
        break;
      case FleetDriverSortKey.customersPerRouteDesc:
        copy.sort((a, b) => b.customersPerRoute.compareTo(a.customersPerRoute));
        break;
      case FleetDriverSortKey.customersPerRouteAsc:
        copy.sort((a, b) => a.customersPerRoute.compareTo(b.customersPerRoute));
        break;
      case FleetDriverSortKey.driverAsc:
        copy.sort((a, b) => (a.displayDriver ?? a.displayMavi).compareTo(b.displayDriver ?? b.displayMavi));
        break;
      case FleetDriverSortKey.partnerAsc:
        copy.sort((a, b) => a.partnerName.compareTo(b.partnerName));
        break;
      case FleetDriverSortKey.customerFairnessDesc:
        copy.sort((a, b) => b.customerVsAvg.compareTo(a.customerVsAvg));
        break;
      case FleetDriverSortKey.customerFairnessAsc:
        copy.sort((a, b) => a.customerVsAvg.compareTo(b.customerVsAvg));
        break;
      case FleetDriverSortKey.topRegionAsc:
        copy.sort((a, b) => (a.topRegion ?? '').compareTo(b.topRegion ?? ''));
        break;
      case FleetDriverSortKey.regionSpreadDesc:
        copy.sort((a, b) => b.regionCount.compareTo(a.regionCount));
        break;
    }
    return copy;
  }

  static List<FleetRegionStat> sortedRegions(List<FleetRegionStat> list, FleetRegionSortKey key) {
    final copy = [...list];
    switch (key) {
      case FleetRegionSortKey.routesDesc:
        copy.sort((a, b) => b.routeCount.compareTo(a.routeCount));
        break;
      case FleetRegionSortKey.routesAsc:
        copy.sort((a, b) => a.routeCount.compareTo(b.routeCount));
        break;
      case FleetRegionSortKey.customersDesc:
        copy.sort((a, b) => b.customerCount.compareTo(a.customerCount));
        break;
      case FleetRegionSortKey.customersAsc:
        copy.sort((a, b) => a.customerCount.compareTo(b.customerCount));
        break;
      case FleetRegionSortKey.regionAsc:
        copy.sort((a, b) => a.region.compareTo(b.region));
        break;
      case FleetRegionSortKey.driversDesc:
        copy.sort((a, b) => b.driverCount.compareTo(a.driverCount));
        break;
    }
    return copy;
  }
}

extension FleetStatsPeriodX on FleetStatsPeriod {
  String get label {
    switch (this) {
      case FleetStatsPeriod.days7:
        return '7 dager';
      case FleetStatsPeriod.days30:
        return '30 dager';
      case FleetStatsPeriod.days90:
        return '90 dager';
      case FleetStatsPeriod.year:
        return '1 år';
      case FleetStatsPeriod.all:
        return 'Alt';
    }
  }

  DateTime? cutoff(DateTime now) {
    switch (this) {
      case FleetStatsPeriod.days7:
        return now.subtract(const Duration(days: 7));
      case FleetStatsPeriod.days30:
        return now.subtract(const Duration(days: 30));
      case FleetStatsPeriod.days90:
        return now.subtract(const Duration(days: 90));
      case FleetStatsPeriod.year:
        return now.subtract(const Duration(days: 365));
      case FleetStatsPeriod.all:
        return null;
    }
  }
}

class FleetVehicleRanking {
  final String vehicleId;
  final String label;
  final String partnerName;
  final int count;

  const FleetVehicleRanking({
    required this.vehicleId,
    required this.label,
    required this.partnerName,
    required this.count,
  });
}

class FleetAnalyticsSummary {
  final int routesReceived;
  final int friDays;
  final int ledigDays;
  final int gittBortDays;
  final int harRuteDays;
  final List<FleetVehicleRanking> topRoutes;
  final List<FleetVehicleRanking> topFri;
  final List<FleetVehicleRanking> topLedig;
  final List<FleetVehicleRanking> topGittBort;
  final double utilizationPercent;
  final int totalSnapshotDays;
  final List<FleetDailyTrendPoint> dailyTrend;
  final Map<String, int> statusBreakdown;
  final List<FleetPartnerAggregate> partnerStats;

  const FleetAnalyticsSummary({
    required this.routesReceived,
    required this.friDays,
    required this.ledigDays,
    required this.gittBortDays,
    required this.harRuteDays,
    required this.topRoutes,
    required this.topFri,
    required this.topLedig,
    required this.topGittBort,
    required this.utilizationPercent,
    required this.totalSnapshotDays,
    required this.dailyTrend,
    required this.statusBreakdown,
    required this.partnerStats,
  });
}

class FleetDailyTrendPoint {
  final DateTime day;
  final int harRute;
  final int fri;
  final int ledig;
  final int gittBort;
  final int routesSent;

  const FleetDailyTrendPoint({
    required this.day,
    required this.harRute,
    required this.fri,
    required this.ledig,
    required this.gittBort,
    required this.routesSent,
  });
}

class FleetPartnerAggregate {
  final String partnerId;
  final String partnerName;
  final int vehicleCount;
  final int routeCount;
  final int harRuteDays;
  final int friDays;
  final int ledigDays;

  const FleetPartnerAggregate({
    required this.partnerId,
    required this.partnerName,
    required this.vehicleCount,
    required this.routeCount,
    required this.harRuteDays,
    required this.friDays,
    required this.ledigDays,
  });

  double get utilizationPercent =>
      (harRuteDays + friDays + ledigDays) > 0 ? (harRuteDays / (harRuteDays + friDays + ledigDays)) * 100 : 0;
}

class FleetAnalyticsService {
  FleetAnalyticsService._();

  static Map<String, int> _countByVehicle(
    Iterable<({String vehicleId, DateTime at})> events,
    DateTime? cutoff,
  ) {
    final m = <String, int>{};
    for (final e in events) {
      if (cutoff != null && e.at.isBefore(cutoff)) continue;
      m[e.vehicleId] = (m[e.vehicleId] ?? 0) + 1;
    }
    return m;
  }

  static List<FleetVehicleRanking> _top(
    Map<String, int> counts,
    Map<String, String> vehicleLabels,
    Map<String, String> partnerNames, {
    int limit = 12,
  }) {
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) {
      return FleetVehicleRanking(
        vehicleId: e.key,
        label: vehicleLabels[e.key] ?? e.key.substring(0, 8),
        partnerName: partnerNames[e.key] ?? '',
        count: e.value,
      );
    }).toList();
  }

  static List<FleetDailyTrendPoint> _dailyTrend({
    required List<PartnerRouteShare> shares,
    required List<PartnerVehicleFleetSnapshot> snapshots,
    required DateTime? cutoff,
    int maxDays = 31,
  }) {
    final dayMap = <DateTime, ({int har, int fri, int led, int gitt, int routes})>{};

    void bump(
      DateTime d,
      ({int har, int fri, int led, int gitt, int routes}) Function(
        ({int har, int fri, int led, int gitt, int routes}) e,
      ) fn,
    ) {
      final key = DateTime(d.year, d.month, d.day);
      if (cutoff != null && key.isBefore(DateTime(cutoff.year, cutoff.month, cutoff.day))) return;
      final cur = dayMap[key] ?? (har: 0, fri: 0, led: 0, gitt: 0, routes: 0);
      dayMap[key] = fn(cur);
    }

    for (final s in shares) {
      if (s.dispatchStatus == 'staged') continue;
      bump(s.createdAt, (e) => (har: e.har, fri: e.fri, led: e.led, gitt: e.gitt, routes: e.routes + 1));
    }
    for (final snap in snapshots) {
      if (cutoff != null && snap.snapshotDate.isBefore(cutoff)) continue;
      final d = snap.snapshotDate;
      switch (snap.status) {
        case 'har_rute':
          bump(d, (e) => (har: e.har + 1, fri: e.fri, led: e.led, gitt: e.gitt, routes: e.routes));
          break;
        case 'fri':
          bump(d, (e) => (har: e.har, fri: e.fri + 1, led: e.led, gitt: e.gitt, routes: e.routes));
          break;
        case 'ledig':
          bump(d, (e) => (har: e.har, fri: e.fri, led: e.led + 1, gitt: e.gitt, routes: e.routes));
          break;
        case 'gitt_bort':
          bump(d, (e) => (har: e.har, fri: e.fri, led: e.led, gitt: e.gitt + 1, routes: e.routes));
          break;
      }
    }

    final days = dayMap.keys.toList()..sort();
    final slice = days.length > maxDays ? days.sublist(days.length - maxDays) : days;
    return slice
        .map(
          (d) => FleetDailyTrendPoint(
            day: d,
            harRute: dayMap[d]!.har,
            fri: dayMap[d]!.fri,
            ledig: dayMap[d]!.led,
            gittBort: dayMap[d]!.gitt,
            routesSent: dayMap[d]!.routes,
          ),
        )
        .toList();
  }

  static List<FleetPartnerAggregate> _partnerStats({
    required List<PartnerRouteShare> shares,
    required List<PartnerVehicleFleetSnapshot> snapshots,
    required Map<String, String> vehicleToPartnerId,
    required Map<String, String> partnerNames,
    required Map<String, int> vehiclesPerPartner,
    required DateTime? cutoff,
  }) {
    final routesByPartner = <String, int>{};
    final harByPartner = <String, int>{};
    final friByPartner = <String, int>{};
    final ledigByPartner = <String, int>{};

    String? pidForVehicle(String? vid) => vid == null ? null : vehicleToPartnerId[vid];

    for (final s in shares) {
      if (s.dispatchStatus == 'staged') continue;
      if (cutoff != null && s.createdAt.isBefore(cutoff)) continue;
      final pid = pidForVehicle(s.partnerVehicleId);
      if (pid == null) continue;
      routesByPartner[pid] = (routesByPartner[pid] ?? 0) + 1;
    }
    for (final snap in snapshots) {
      if (cutoff != null && snap.snapshotDate.isBefore(cutoff)) continue;
      final pid = vehicleToPartnerId[snap.partnerVehicleId];
      if (pid == null) continue;
      switch (snap.status) {
        case 'har_rute':
          harByPartner[pid] = (harByPartner[pid] ?? 0) + 1;
          break;
        case 'fri':
          friByPartner[pid] = (friByPartner[pid] ?? 0) + 1;
          break;
        case 'ledig':
          ledigByPartner[pid] = (ledigByPartner[pid] ?? 0) + 1;
          break;
      }
    }

    final ids = <String>{
      ...partnerNames.keys,
      ...routesByPartner.keys,
      ...harByPartner.keys,
    };
    final list = ids
        .map(
          (id) => FleetPartnerAggregate(
            partnerId: id,
            partnerName: partnerNames[id] ?? 'Partner',
            vehicleCount: vehiclesPerPartner[id] ?? 0,
            routeCount: routesByPartner[id] ?? 0,
            harRuteDays: harByPartner[id] ?? 0,
            friDays: friByPartner[id] ?? 0,
            ledigDays: ledigByPartner[id] ?? 0,
          ),
        )
        .toList()
      ..sort((a, b) => b.routeCount.compareTo(a.routeCount));
    return list;
  }

  static FleetAnalyticsSummary build({
    required FleetStatsPeriod period,
    required List<PartnerRouteShare> shares,
    required List<PartnerVehicleFleetSnapshot> snapshots,
    required Map<String, String> vehicleLabels,
    required Map<String, String> partnerNames,
    Map<String, String>? vehicleToPartnerId,
    Map<String, int>? vehiclesPerPartner,
  }) {
    final now = DateTime.now();
    final cutoff = period.cutoff(now);

    final routeEvents = <({String vehicleId, DateTime at})>[];
    for (final s in shares) {
      final vid = s.partnerVehicleId;
      if (vid == null) continue;
      if (s.dispatchStatus == 'staged') continue;
      routeEvents.add((vehicleId: vid, at: s.createdAt));
    }

    var fri = 0, ledig = 0, gitt = 0, har = 0;
    final friByV = <String, int>{};
    final ledigByV = <String, int>{};
    final gittByV = <String, int>{};
    final harByV = <String, int>{};

    for (final snap in snapshots) {
      if (cutoff != null && snap.snapshotDate.isBefore(cutoff)) continue;
      switch (snap.status) {
        case 'fri':
          fri++;
          friByV[snap.partnerVehicleId] = (friByV[snap.partnerVehicleId] ?? 0) + 1;
          break;
        case 'ledig':
          ledig++;
          ledigByV[snap.partnerVehicleId] = (ledigByV[snap.partnerVehicleId] ?? 0) + 1;
          break;
        case 'gitt_bort':
          gitt++;
          gittByV[snap.partnerVehicleId] = (gittByV[snap.partnerVehicleId] ?? 0) + 1;
          break;
        case 'har_rute':
          har++;
          harByV[snap.partnerVehicleId] = (harByV[snap.partnerVehicleId] ?? 0) + 1;
          break;
      }
    }

    final routesByV = _countByVehicle(routeEvents, cutoff);
    final totalSnaps = fri + ledig + gitt + har;
    final utilization = totalSnaps > 0 ? (har / totalSnaps) * 100 : 0.0;

    final v2p = vehicleToPartnerId ?? {};
    final vpp = vehiclesPerPartner ?? {};
    final partnerIdNames = <String, String>{};
    for (final e in v2p.entries) {
      final pname = partnerNames[e.key];
      if (pname != null) partnerIdNames[e.value] = pname;
    }

    return FleetAnalyticsSummary(
      routesReceived: routeEvents.where((e) => cutoff == null || !e.at.isBefore(cutoff)).length,
      friDays: fri,
      ledigDays: ledig,
      gittBortDays: gitt,
      harRuteDays: har,
      topRoutes: _top(routesByV, vehicleLabels, partnerNames),
      topFri: _top(friByV, vehicleLabels, partnerNames),
      topLedig: _top(ledigByV, vehicleLabels, partnerNames),
      topGittBort: _top(gittByV, vehicleLabels, partnerNames),
      utilizationPercent: utilization,
      totalSnapshotDays: totalSnaps,
      dailyTrend: _dailyTrend(shares: shares, snapshots: snapshots, cutoff: cutoff),
      statusBreakdown: {
        'har_rute': har,
        'ledig': ledig,
        'fri': fri,
        'gitt_bort': gitt,
      },
      partnerStats: _partnerStats(
        shares: shares,
        snapshots: snapshots,
        vehicleToPartnerId: v2p,
        partnerNames: partnerIdNames,
        vehiclesPerPartner: vpp,
        cutoff: cutoff,
      ),
    );
  }

  static int _customersOnShare(PartnerRouteShare s) {
    if (s.customerCount != null && s.customerCount! > 0) return s.customerCount!;
    final text = s.pdfSearchText;
    if (text == null || text.trim().isEmpty) return 0;
    return RoutePdfTextService.parseCustomers(text).length;
  }

  static bool _shareInRange(PartnerRouteShare s, DateTime start, DateTime end) {
    if (s.isStaged) return false;
    final d = DateTime(s.shareDate.year, s.shareDate.month, s.shareDate.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  static bool _snapInRange(PartnerVehicleFleetSnapshot snap, DateTime start, DateTime end) {
    final d = DateTime(snap.snapshotDate.year, snap.snapshotDate.month, snap.snapshotDate.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  static bool _assignInRange(MaviDriverDayAssignment a, DateTime start, DateTime end) {
    final d = DateTime(a.assignmentDate.year, a.assignmentDate.month, a.assignmentDate.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  static String _regionLabelForShift(FleetShiftDefinition shift) {
    final r = shift.regionGroup?.trim();
    if (r != null && r.isNotEmpty) return r;
    return 'Ukjent område';
  }

  static String _regionLabelForShare(
    PartnerRouteShare share,
    Map<String, String> regionByShiftId,
  ) {
    final sid = share.shiftId;
    if (sid != null) {
      final fromShift = regionByShiftId[sid];
      if (fromShift != null && fromShift.trim().isNotEmpty) {
        return fromShift.trim();
      }
    }
    return 'Ukjent område';
  }

  static List<FleetRegionStat> _buildRegionStats(List<FleetDriverStat> drivers) {
    final routesByRegion = <String, int>{};
    final customersByRegion = <String, int>{};
    final driversByRegion = <String, Set<String>>{};
    final topByRegion = <String, ({String mavi, String? driver, int routes})>{};

    for (final d in drivers) {
      for (final e in d.routesByRegion.entries) {
        final region = e.key;
        routesByRegion[region] = (routesByRegion[region] ?? 0) + e.value;
        driversByRegion.putIfAbsent(region, () => {}).add(d.vehicleId);
        final cur = topByRegion[region];
        if (cur == null || e.value > cur.routes) {
          topByRegion[region] = (mavi: d.displayMavi, driver: d.displayDriver, routes: e.value);
        }
      }
      for (final e in d.customersByRegion.entries) {
        customersByRegion[e.key] = (customersByRegion[e.key] ?? 0) + e.value;
      }
    }

    return routesByRegion.keys
        .map(
          (region) => FleetRegionStat(
            region: region,
            routeCount: routesByRegion[region] ?? 0,
            customerCount: customersByRegion[region] ?? 0,
            driverCount: driversByRegion[region]?.length ?? 0,
            topDriverMavi: topByRegion[region]?.mavi,
            topDriverName: topByRegion[region]?.driver,
            topDriverRoutes: topByRegion[region]?.routes ?? 0,
          ),
        )
        .toList()
      ..sort((a, b) => b.routeCount.compareTo(a.routeCount));
  }

  static FleetDriverStatsBundle buildDriverStats({
    required FleetCalendarPeriod period,
    required List<PartnerRouteShare> shares,
    required List<PartnerVehicleFleetSnapshot> snapshots,
    required List<FleetPartnerVehicleRow> fleet,
    List<FleetShiftDefinition> shifts = const [],
    List<MaviDriverDayAssignment> dayAssignments = const [],
    DateTime? referenceNow,
  }) {
    final now = referenceNow ?? DateTime.now();
    final start = period.rangeStart(now);
    final end = DateTime(now.year, now.month, now.day);

    final shiftById = <String, FleetShiftDefinition>{
      for (final sh in shifts) sh.id: sh,
    };

    final vehicleMeta = <String, ({String? driver, String mavi, String partner})>{};
    for (final row in fleet) {
      final v = row.vehicle;
      final driver = v.driverName?.trim();
      vehicleMeta[v.id] = (
        driver: driver != null && driver.isNotEmpty ? driver : null,
        mavi: MaviUnitCodes.normalize(v.unitCode),
        partner: row.partner.name,
      );
    }

    final regionByShiftId = <String, String>{
      for (final sh in shifts)
        if (sh.regionGroup != null && sh.regionGroup!.trim().isNotEmpty) sh.id: sh.regionGroup!.trim(),
    };

    final routesByV = <String, int>{};
    final customersByV = <String, int>{};
    final routesByVRegion = <String, Map<String, int>>{};
    final customersByVRegion = <String, Map<String, int>>{};
    final friByV = <String, int>{};

    String dayKey(DateTime d) => d.toIso8601String().split('T').first;
    String vehDayKey(String vid, String dk) => '$vid|$dk';

    final shareByVehDay = <String, PartnerRouteShare>{};
    for (final s in shares) {
      if (!_shareInRange(s, start, end)) continue;
      if (s.dispatchStatus == 'staged') continue;
      final vid = s.partnerVehicleId;
      if (vid == null) continue;
      final k = vehDayKey(vid, dayKey(s.shareDate));
      final prev = shareByVehDay[k];
      if (prev == null || s.createdAt.isAfter(prev.createdAt)) {
        shareByVehDay[k] = s;
      }
    }

    final assignByVehDay = <String, MaviDriverDayAssignment>{};
    for (final a in dayAssignments) {
      if (!_assignInRange(a, start, end)) continue;
      final k = vehDayKey(a.partnerVehicleId, dayKey(a.assignmentDate));
      final prev = assignByVehDay[k];
      final aAt = a.updatedAt ?? a.assignmentDate;
      final pAt = prev?.updatedAt ?? prev?.assignmentDate;
      if (prev == null || (pAt != null && aAt.isAfter(pAt))) {
        assignByVehDay[k] = a;
      }
    }

    final allVehDays = <String>{...shareByVehDay.keys, ...assignByVehDay.keys};

    void addRoute(String vid, String region) {
      routesByV[vid] = (routesByV[vid] ?? 0) + 1;
      final rMap = routesByVRegion.putIfAbsent(vid, () => {});
      rMap[region] = (rMap[region] ?? 0) + 1;
    }

    void addCustomers(String vid, String region, int cust) {
      if (cust <= 0) return;
      customersByV[vid] = (customersByV[vid] ?? 0) + cust;
      final cMap = customersByVRegion.putIfAbsent(vid, () => {});
      cMap[region] = (cMap[region] ?? 0) + cust;
    }

    bool isFriShift(FleetShiftDefinition shift) {
      final n = shift.name.toLowerCase();
      return n.contains('fri') && !n.contains('ledig');
    }

    for (final k in allVehDays) {
      final share = shareByVehDay[k];
      final assign = assignByVehDay[k];
      final vid = share?.partnerVehicleId ?? assign?.partnerVehicleId;
      if (vid == null) continue;

      final assignAt = assign?.updatedAt ?? assign?.assignmentDate;
      final shareAt = share?.createdAt;
      final assignWins = assign != null &&
          (shareAt == null || (assignAt != null && !assignAt.isBefore(shareAt)));

      final shift = assign != null ? shiftById[assign.shiftId] : null;

      if (assignWins && shift != null && shift.isAvailability && isFriShift(shift)) {
        friByV[vid] = (friByV[vid] ?? 0) + 1;
        continue;
      }

      String region;
      if (assignWins && shift != null && !shift.isAvailability) {
        region = _regionLabelForShift(shift);
      } else if (share != null) {
        region = _regionLabelForShare(share, regionByShiftId);
      } else {
        continue;
      }

      final hasRouteDay = (assignWins && shift != null && !shift.isAvailability) || share != null;
      if (hasRouteDay) addRoute(vid, region);

      if (share != null && !(assignWins && shift != null && isFriShift(shift))) {
        addCustomers(vid, region, _customersOnShare(share));
      }
    }

    for (final snap in snapshots) {
      if (!_snapInRange(snap, start, end)) continue;
      if (snap.status != 'fri') continue;
      final k = vehDayKey(snap.partnerVehicleId, dayKey(snap.snapshotDate));
      if (assignByVehDay.containsKey(k)) continue;
      friByV[snap.partnerVehicleId] = (friByV[snap.partnerVehicleId] ?? 0) + 1;
    }

    final ids = <String>{
      ...routesByV.keys,
      ...friByV.keys,
      ...assignByVehDay.keys.map((k) => k.split('|').first),
      ...vehicleMeta.keys,
    };

    var drivers = ids.map((vid) {
      final meta = vehicleMeta[vid];
      final mavi = meta?.mavi ?? 'MAVI-${vid.substring(0, 6)}';
      return FleetDriverStat(
        vehicleId: vid,
        driverName: meta?.driver,
        maviLabel: mavi,
        partnerName: meta?.partner ?? 'Ukjent partner',
        routeCount: routesByV[vid] ?? 0,
        customerCount: customersByV[vid] ?? 0,
        friDays: friByV[vid] ?? 0,
        routesByRegion: Map.unmodifiable(routesByVRegion[vid] ?? const {}),
        customersByRegion: Map.unmodifiable(customersByVRegion[vid] ?? const {}),
      );
    }).where((d) => d.routeCount > 0 || d.customerCount > 0 || d.friDays > 0).toList();

    final totalRoutes = routesByV.values.fold<int>(0, (a, b) => a + b);
    final totalCustomers = customersByV.values.fold<int>(0, (a, b) => a + b);
    final withRoutes = drivers.where((d) => d.routeCount > 0).toList();
    final avgRoutes = withRoutes.isEmpty ? 0.0 : totalRoutes / withRoutes.length;
    final avgCustomers = withRoutes.isEmpty ? 0.0 : totalCustomers / withRoutes.length;

    drivers = drivers
        .map(
          (d) => FleetDriverStat(
            vehicleId: d.vehicleId,
            driverName: d.driverName,
            maviLabel: d.maviLabel,
            partnerName: d.partnerName,
            routeCount: d.routeCount,
            customerCount: d.customerCount,
            friDays: d.friDays,
            routeVsAvg: d.routeCount - avgRoutes,
            customerVsAvg: d.customerCount - avgCustomers,
            routesByRegion: d.routesByRegion,
            customersByRegion: d.customersByRegion,
          ),
        )
        .toList()
      ..sort((a, b) {
        final c = b.routeCount.compareTo(a.routeCount);
        if (c != 0) return c;
        return b.customerCount.compareTo(a.customerCount);
      });

    FleetDriverStat? mostRoutes;
    FleetDriverStat? leastRoutes;
    FleetDriverStat? mostCustomers;
    FleetDriverStat? leastCustomers;
    FleetDriverStat? mostFri;

    if (withRoutes.isNotEmpty) {
      mostRoutes = withRoutes.reduce((a, b) => a.routeCount >= b.routeCount ? a : b);
      leastRoutes = withRoutes.reduce((a, b) => a.routeCount <= b.routeCount ? a : b);
      final withCust = drivers.where((d) => d.customerCount > 0).toList();
      if (withCust.isNotEmpty) {
        mostCustomers = withCust.reduce((a, b) => a.customerCount >= b.customerCount ? a : b);
        leastCustomers = withCust.reduce((a, b) => a.customerCount <= b.customerCount ? a : b);
      }
    }
    final friList = drivers.where((d) => d.friDays > 0).toList();
    if (friList.isNotEmpty) {
      mostFri = friList.reduce((a, b) => a.friDays >= b.friDays ? a : b);
    }

    final regions = _buildRegionStats(drivers);
    FleetRegionStat? mostActiveRegion;
    if (regions.isNotEmpty) {
      mostActiveRegion = regions.reduce((a, b) => a.routeCount >= b.routeCount ? a : b);
    }

    return FleetDriverStatsBundle(
      period: period,
      drivers: drivers,
      regions: regions,
      totalRoutes: totalRoutes,
      totalCustomers: totalCustomers,
      activeMaviCount: fleet.length,
      avgRoutesPerMavi: avgRoutes,
      avgCustomersPerMavi: avgCustomers,
      mostRoutes: mostRoutes,
      leastRoutes: leastRoutes,
      mostCustomers: mostCustomers,
      leastCustomers: leastCustomers,
      mostFri: mostFri,
      mostActiveRegion: mostActiveRegion,
    );
  }
}
