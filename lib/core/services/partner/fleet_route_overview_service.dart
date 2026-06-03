import 'dart:typed_data';

import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/mavi_driver_day_assignment.dart';
import 'fleet_shift_seed.dart';
import 'mavi_unit_codes.dart';
import 'partner_service.dart';
import 'fleet_mavi_day_sync.dart';
import 'route_overview_excel_import.dart';

class FleetRouteOverviewImportReport {
  final int rowsParsed;
  final int cellsWritten;
  final int cellsSkipped;
  final List<String> warnings;

  const FleetRouteOverviewImportReport({
    required this.rowsParsed,
    required this.cellsWritten,
    required this.cellsSkipped,
    required this.warnings,
  });
}

/// Ruteoversikt: daglige skift per MAVI, Excel-import, synk mot flåte-snapshots.
class FleetRouteOverviewService {
  FleetRouteOverviewService._();

  static int maviNumericSort(String unitCode) {
    final m = RegExp(r'M0*(\d{1,5})').firstMatch(MaviUnitCodes.compactLabel(unitCode));
    return int.tryParse(m?.group(1) ?? '99999') ?? 99999;
  }

  static List<FleetPartnerVehicleRow> sortDriversFromM01(List<FleetPartnerVehicleRow> fleet) {
    final list = fleet.where((r) {
      final n = maviNumericSort(r.vehicle.unitCode);
      return n >= 1 && n < 9000;
    }).toList();
    list.sort((a, b) {
      final cmp = maviNumericSort(a.vehicle.unitCode).compareTo(maviNumericSort(b.vehicle.unitCode));
      if (cmp != 0) return cmp;
      return a.partner.name.compareTo(b.partner.name);
    });
    return list;
  }

  static Future<List<MaviDriverDayAssignment>> fetchAssignments({
    required String companyId,
    required DateTime from,
    required DateTime to,
  }) {
    return PartnerService.fetchMaviDayAssignments(
      companyId: companyId,
      from: from,
      to: to,
    );
  }

  static Future<void> saveAssignment({
    required String companyId,
    required String partnerVehicleId,
    required DateTime date,
    required String shiftId,
    String? notes,
    List<FleetShiftDefinition>? shiftsForSync,
  }) async {
    await FleetMaviDaySync.apply(
      companyId: companyId,
      partnerVehicleId: partnerVehicleId,
      date: date,
      shiftId: shiftId,
      notes: notes ?? 'Ruteoversikt',
    );
  }

  static Future<void> clearAssignment({
    required String companyId,
    required String partnerVehicleId,
    required DateTime date,
  }) {
    return PartnerService.deleteMaviDayAssignment(
      companyId: companyId,
      partnerVehicleId: partnerVehicleId,
      date: date,
    );
  }

  static Future<FleetRouteOverviewImportReport> importFromExcel({
    required String companyId,
    required Uint8List bytes,
    required List<FleetPartnerVehicleRow> fleet,
    required List<FleetShiftDefinition> shifts,
    bool replaceExisting = false,
  }) async {
    await PartnerService.ensureCanonicalFleetShifts(companyId);
    final allShifts = shifts.isNotEmpty ? shifts : await PartnerService.fetchFleetShifts(companyId);

    final parsed = RouteOverviewExcelImport.parse(bytes);
    final vehicleByCode = <String, FleetPartnerVehicleRow>{};
    for (final row in fleet) {
      vehicleByCode[MaviUnitCodes.normalize(row.vehicle.unitCode)] = row;
    }

    var written = 0;
    var skipped = 0;
    final warnings = [...parsed.warnings];

    if (replaceExisting && parsed.days.isNotEmpty) {
      final from = parsed.days.reduce((a, b) => a.isBefore(b) ? a : b);
      final to = parsed.days.reduce((a, b) => a.isAfter(b) ? a : b);
      await PartnerService.deleteMaviDayAssignmentsInRange(
        companyId: companyId,
        from: from,
        to: to,
      );
    }

    for (final row in parsed.rows) {
      final vehicle = vehicleByCode[row.normalizedUnitCode];
      if (vehicle == null) {
        skipped += row.shiftLabelByDay.length;
        warnings.add('Fant ikke ${row.maviLabel} i flåten — hoppet over rad.');
        continue;
      }

      for (final entry in row.shiftLabelByDay.entries) {
        final shift = RouteOverviewExcelImport.matchShift(entry.value, allShifts);
        if (shift == null) {
          skipped++;
          warnings.add('${row.maviLabel} ${entry.key.toIso8601String().split('T').first}: ukjent skift «${entry.value}»');
          continue;
        }
        final note = row.notesByDay[entry.key] ?? 'Importert fra Ruteoversikt 2026';
        await saveAssignment(
          companyId: companyId,
          partnerVehicleId: vehicle.vehicle.id,
          date: entry.key,
          shiftId: shift.id,
          notes: note,
          shiftsForSync: allShifts,
        );
        written++;
      }
    }

    return FleetRouteOverviewImportReport(
      rowsParsed: parsed.rows.length,
      cellsWritten: written,
      cellsSkipped: skipped,
      warnings: warnings,
    );
  }

  static String statusForShift(FleetShiftDefinition shift) =>
      FleetMaviDaySync.snapshotStatusForShift(shift);

  static List<String> canonicalShiftHints() => FleetShiftSeed.canonicalNames;
}
