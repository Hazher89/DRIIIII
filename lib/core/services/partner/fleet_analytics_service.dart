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
  });
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

  static FleetAnalyticsSummary build({
    required FleetStatsPeriod period,
    required List<PartnerRouteShare> shares,
    required List<PartnerVehicleFleetSnapshot> snapshots,
    required Map<String, String> vehicleLabels,
    required Map<String, String> partnerNames,
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
    );
  }
}
