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

  List<PartnerRouteShare> get routesToday => routes.where(ownerRouteIsToday).toList();

  List<PartnerRouteShare> get routesUpcoming =>
      routes.where((r) => ownerRouteIsActive(r) && !ownerRouteIsToday(r)).toList();

  List<PartnerRouteShare> get routesArchive {
    final past = routes
        .where((r) => ownerRouteIsPast(r) || (!ownerRouteIsActive(r) && !ownerRouteIsFuture(r)))
        .toList();
    past.sort((a, b) => ownerRouteCalendarDay(b).compareTo(ownerRouteCalendarDay(a)));
    return past;
  }

  int get pendingAck => routes.where((r) => r.requiresAck).length;

  static Future<DriverPortalData> load({
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
    final routes = partner.routesOwnerOnly
        ? const <PartnerRouteShare>[]
        : await PartnerService.fetchRouteShares(
            partner.id,
            partnerVehicleId: partnerVehicleId,
            sentOnly: true,
          );
    final docs = await PartnerService.fetchDriverPortalDocuments(partner.id);
    final shiftList = await PartnerService.fetchFleetShifts(partner.companyId);
    return DriverPortalData(
      partner: partner,
      vehicle: vehicle,
      routes: routes,
      documents: docs,
      shiftsById: {for (final s in shiftList) s.id: s},
    );
  }
}
