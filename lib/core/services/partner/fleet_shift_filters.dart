import '../../../models/partner/fleet_shift.dart';

/// Filtrering av flåteskift for rute-PDF og publisering.
class FleetShiftFilters {
  FleetShiftFilters._();

  /// Geilo brukes ikke i MAVI-ruteområdet — ekskluder fra auto og dropdown.
  static bool isGeilo(FleetShiftDefinition shift) {
    final region = (shift.regionGroup ?? '').toLowerCase();
    final name = shift.name.toLowerCase();
    return region.contains('geilo') || name.contains('geilo');
  }

  /// Ruteskift som kan velges/fordeles (uten Geilo og uten tilgjengelighet).
  static List<FleetShiftDefinition> forRouteAssignment(
    Iterable<FleetShiftDefinition> shifts,
  ) {
    return shifts
        .where((s) => !s.isAvailability && !isGeilo(s))
        .toList();
  }
}
