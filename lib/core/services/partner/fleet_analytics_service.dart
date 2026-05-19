import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';

enum FleetStatsPeriod { days7, days30, days90, year, all }

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
}
