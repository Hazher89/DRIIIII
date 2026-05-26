import '../../core/services/partner/partner_service.dart';
import '../../models/partner/partner.dart';

/// Flåte hentet fra DriftPro (partners + MAVI-biler) — masterdata, ikke duplikat.
class LmFleetSnapshot {
  final DateTime syncedAt;
  final List<FleetPartnerVehicleRow> maviVehicles;
  final List<Partner> partners;
  final int driverPortalCount;

  const LmFleetSnapshot({
    required this.syncedAt,
    required this.maviVehicles,
    required this.partners,
    required this.driverPortalCount,
  });

  int get vehicleCount => maviVehicles.length;
  int get partnerCount => partners.length;
}
