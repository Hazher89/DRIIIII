import '../../../models/partner/fleet_shift.dart';
import 'partner_service.dart';

/// Én plan per MAVI og dag: [mavi_driver_day_assignments] + flåte-snapshot.
/// Siste skriving vinner — brukes fra ruteoversikt, ruteplanlegging og masse/SAP.
class FleetMaviDaySync {
  FleetMaviDaySync._();

  static String snapshotStatusForShift(FleetShiftDefinition shift, {bool hasRoute = false}) {
    if (hasRoute) return 'har_rute';
    if (shift.isAvailability) {
      final n = shift.name.toLowerCase();
      if (n.contains('fri') && !n.contains('ledig')) return 'fri';
      if (n.contains('syk')) return 'fri';
      if (n.contains('gitt')) return 'gitt_bort';
      return 'ledig';
    }
    return 'ledig';
  }

  static Future<void> apply({
    required String companyId,
    required String partnerVehicleId,
    required DateTime date,
    required String shiftId,
    String? notes,
    String? partnerRouteShareId,
    List<FleetShiftDefinition>? shifts,
  }) async {
    await PartnerService.upsertMaviDayAssignment(
      companyId: companyId,
      partnerVehicleId: partnerVehicleId,
      date: date,
      shiftId: shiftId,
      notes: notes,
    );

    final shiftList = shifts ?? await PartnerService.fetchFleetShifts(companyId);
    FleetShiftDefinition? shift;
    for (final s in shiftList) {
      if (s.id == shiftId) {
        shift = s;
        break;
      }
    }
    if (shift == null) return;

    final dn = DateTime(date.year, date.month, date.day);
    await PartnerService.upsertFleetSnapshot(
      PartnerVehicleFleetSnapshot(
        id: '',
        companyId: companyId,
        partnerVehicleId: partnerVehicleId,
        snapshotDate: dn,
        shiftId: shiftId,
        status: snapshotStatusForShift(shift, hasRoute: partnerRouteShareId != null),
        partnerRouteShareId: partnerRouteShareId,
        notes: notes,
        createdAt: DateTime.now(),
      ),
    );
  }

  static Future<String?> firstLedigShiftId(String companyId) async {
    final shifts = await PartnerService.fetchFleetShifts(companyId);
    for (final s in shifts) {
      if (s.isAvailability && s.name.toUpperCase().contains('LEDIG')) {
        return s.id;
      }
    }
    return shifts.isNotEmpty ? shifts.first.id : null;
  }
}
