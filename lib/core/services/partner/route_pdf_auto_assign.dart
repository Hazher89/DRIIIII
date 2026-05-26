import 'dart:typed_data';

import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';
import 'postal_code_registry.dart';
import 'route_pdf_text_service.dart';
import 'route_shift_resolver.dart';
import 'route_time_band.dart';

/// Alt som leses automatisk fra en rute-PDF (sjåfør, tid, postkoder, skift).
class RoutePdfAutoAssign {
  final String? maviCode;
  final String? driverNameFromPdf;
  final String? driverNameOnVehicle;
  final bool driverNameMatchesVehicle;
  final DateTime routeDate;
  final DateTime? routeStartAt;
  final String timeBand;
  final RoutePostalAnalysis postal;
  final FleetShiftDefinition? shift;
  final String? shiftLabel;

  const RoutePdfAutoAssign({
    this.maviCode,
    this.driverNameFromPdf,
    this.driverNameOnVehicle,
    this.driverNameMatchesVehicle = false,
    required this.routeDate,
    this.routeStartAt,
    this.timeBand = 'dag',
    required this.postal,
    this.shift,
    this.shiftLabel,
  });

  static Future<RoutePdfAutoAssign> analyze({
    required Uint8List bytes,
    required DateTime fallbackDate,
    required List<FleetShiftDefinition> shifts,
    PartnerVehicle? vehicle,
    RoutePdfParseBundle? bundle,
  }) async {
    await PostalCodeRegistry.ensureLoaded();
    final parsed = bundle ?? RoutePdfTextService.parseBundle(bytes, fallbackDate: fallbackDate);
    final text = parsed.searchText;
    final meta = parsed.meta;
    final mavi = meta.maviCode ?? RoutePdfTextService.extractResourceIdFromBytes(bytes);
    final driverPdf = RoutePdfTextService.parseDriverName(parsed.headerText) ??
        RoutePdfTextService.parseDriverName(text);
    final schedule = parsed.schedule;
    final band = RouteTimeBand.fromDateTime(schedule.routeStartAt);
    final postal = await RouteShiftResolver.analyzePdfText(text);
    final region = postal.bestEffortRegion;
    final shift = region != null
        ? RouteShiftResolver.pickShiftForRegion(
            shifts: shifts,
            region: region,
            routeStartAt: schedule.routeStartAt,
          )
        : null;

    final vehicleDriver = vehicle?.driverName?.trim();
    final matches = driverPdf != null &&
        vehicleDriver != null &&
        vehicleDriver.isNotEmpty &&
        _norm(driverPdf) == _norm(vehicleDriver);

    return RoutePdfAutoAssign(
      maviCode: mavi,
      driverNameFromPdf: driverPdf,
      driverNameOnVehicle: vehicleDriver,
      driverNameMatchesVehicle: matches,
      routeDate: schedule.routeDate,
      routeStartAt: schedule.routeStartAt,
      timeBand: band,
      postal: postal,
      shift: shift,
      shiftLabel: shift?.name,
    );
  }

  static String composeAutoNotes(RoutePdfAutoAssign a, {String? existing}) {
    final parts = <String>[];
    if (a.driverNameFromPdf != null && a.driverNameFromPdf!.isNotEmpty) {
      parts.add('Sjåfør (PDF): ${a.driverNameFromPdf}');
    }
    parts.add(
      'Rutedato (PDF): ${a.routeDate.day.toString().padLeft(2, '0')}.'
      '${a.routeDate.month.toString().padLeft(2, '0')}.${a.routeDate.year}',
    );
    if (a.postal.bestEffortRegion != null) {
      final conf = a.postal.hasConfidentRegion ? '' : ' (gjetning)';
      parts.add(
        'Område: ${a.postal.bestEffortRegion} (${a.postal.dominantCount} postnr, ${RouteTimeBand.label(a.timeBand)})$conf',
      );
    }
    if (a.shiftLabel != null) {
      parts.add('Skift (auto): ${a.shiftLabel}');
    }
    final extra = existing?.trim() ?? '';
    if (extra.isNotEmpty) parts.add(extra);
    return parts.join('\n');
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll('æ', 'ae').replaceAll('ø', 'o').replaceAll('å', 'aa').trim();
}
