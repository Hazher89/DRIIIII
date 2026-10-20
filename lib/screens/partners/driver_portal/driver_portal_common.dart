import '../../../core/services/partner/partner_portal_data_cache.dart';
import '../../../core/services/partner/partner_portal_scope.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../owner_portal/owner_portal_common.dart';

/// Data for én sjåfør (én bil).
class DriverPortalData {
  final Partner partner;
  final PartnerVehicle? vehicle;
  final List<PartnerRouteShare> routes;
  final List<PartnerDocument> documents;
  final Map<String, FleetShiftDefinition> shiftsById;

  const DriverPortalData({
    required this.partner,
    required this.vehicle,
    required this.routes,
    required this.documents,
    required this.shiftsById,
  });

  /// I dag + fremover (inkl. ventende aksept og allerede aksepterte).
  List<PartnerRouteShare> get routesKommende {
    final upcoming = routes.where((r) => !ownerRouteIsPast(r)).toList();
    upcoming.sort((a, b) {
      final aPending = ownerRouteNeedsPortalAck(a);
      final bPending = ownerRouteNeedsPortalAck(b);
      if (aPending && !bPending) return -1;
      if (bPending && !aPending) return 1;
      return ownerRouteCalendarDay(a).compareTo(ownerRouteCalendarDay(b));
    });
    return upcoming;
  }

  /// Kun ruter som trenger aksept (for banner / hurtigvalg).
  List<PartnerRouteShare> get routesNew {
    final pending = routes.where(ownerRouteNeedsPortalAck).toList();
    pending.sort((a, b) => ownerRouteCalendarDay(a).compareTo(ownerRouteCalendarDay(b)));
    return pending;
  }

  List<PartnerRouteShare> get routesToday => routes.where(ownerRouteIsToday).toList();

  List<PartnerRouteShare> get routesUpcoming =>
      routes.where((r) => ownerRouteIsActive(r) && !ownerRouteIsToday(r)).toList();

  /// Kalenderdager før i dag.
  List<PartnerRouteShare> get routesArchive {
    final past = routes.where(ownerRouteIsPast).toList();
    past.sort((a, b) => ownerRouteCalendarDay(b).compareTo(ownerRouteCalendarDay(a)));
    return past;
  }

  int get pendingAck => routes.where(ownerRouteNeedsPortalAck).length;

  static Future<DriverPortalData> load({
    required Partner partner,
    required String? partnerVehicleId,
    bool forceRefresh = false,
  }) async {
    final key = PartnerPortalDataCache.driverKey(partner, partnerVehicleId);
    if (!forceRefresh) {
      final cached = PartnerPortalDataCache.get<DriverPortalData>(key);
      if (cached != null) return cached;
      final inflight = PartnerPortalDataCache.inFlight<DriverPortalData>(key);
      if (inflight != null) return inflight;
    }

    final future = _loadFresh(
      partner: partner,
      partnerVehicleId: partnerVehicleId,
    );
    PartnerPortalDataCache.setInFlight(key, future);
    try {
      final data = await future;
      PartnerPortalDataCache.put(key, data);
      return data;
    } finally {
      PartnerPortalDataCache.clearInFlight(key);
    }
  }

  static Future<DriverPortalData> _loadFresh({
    required Partner partner,
    required String? partnerVehicleId,
  }) async {
    await PartnerPortalScope.assertAccess(
      partnerId: partner.id,
      partnerVehicleId: partnerVehicleId,
    );
    final vehicles = await PartnerService.fetchVehicles(partner.id);
    PartnerVehicle? vehicle;
    if (partnerVehicleId != null) {
      for (final v in vehicles) {
        if (v.id == partnerVehicleId) {
          vehicle = v;
          break;
        }
      }
    }

    final results = await Future.wait<Object>([
      partner.routesOwnerOnly
          ? Future<List<PartnerRouteShare>>.value(const [])
          : PartnerService.fetchRouteShares(
              partner.id,
              partnerVehicleId: partnerVehicleId,
              sentOnly: true,
            ),
      PartnerService.fetchDriverPortalDocuments(partner.id),
      PartnerService.fetchFleetShifts(partner.companyId),
    ]);

    return DriverPortalData(
      partner: partner,
      vehicle: vehicle,
      routes: results[0] as List<PartnerRouteShare>,
      documents: results[1] as List<PartnerDocument>,
      shiftsById: {
        for (final s in results[2] as List<FleetShiftDefinition>) s.id: s,
      },
    );
  }
}
