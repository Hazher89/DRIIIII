import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';
import 'fleet_shift_filters.dart';
import 'partner_service.dart';
import 'postal_code_registry.dart';
import 'postal_region_mapper.dart';
import 'route_pdf_text_service.dart';
import 'route_time_band.dart';

/// Resultat av postkode-analyse fra rute-PDF.
class RoutePostalAnalysis {
  final List<String> postalCodes;
  final Map<String, int> regionCounts;
  final String? dominantRegion;
  final int dominantCount;
  final int deliveryStopCount;
  /// Område for første leveringsstopp (brukes ved uavgjort mellom få stopp).
  final String? firstStopRegion;

  const RoutePostalAnalysis({
    required this.postalCodes,
    required this.regionCounts,
    this.dominantRegion,
    required this.dominantCount,
    this.deliveryStopCount = 0,
    this.firstStopRegion,
  });

  /// Stopp-liste: flertall blant leveringer (min. 3 stopp eller ≥60 %).
  /// Fulltekst-fallback: minst 4 postnummer i samme område.
  bool get hasConfidentRegion {
    if (dominantRegion == null || dominantCount <= 0) return false;
    if (deliveryStopCount >= 2) {
      final need = _stopMajorityThreshold(deliveryStopCount);
      return dominantCount >= need;
    }
    if (deliveryStopCount == 1) return dominantCount >= 1;
    return dominantCount >= RouteShiftResolver.minPostalCodesPerRegion;
  }

  /// Beste gjetning når vi har minst ett postnr/område — også 1–2 stopp og uavgjort.
  String? get bestEffortRegion {
    if (dominantRegion != null) return dominantRegion;
    if (firstStopRegion != null) return firstStopRegion;
    if (regionCounts.isEmpty) return null;
    final sorted = regionCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  bool get hasRegionSignal => bestEffortRegion != null;

  /// Flertall: 2 av 3, 2 av 4, ellers ~60 % (minst 2).
  static int _stopMajorityThreshold(int stopCount) {
    if (stopCount <= 1) return 1;
    if (stopCount <= 4) return (stopCount / 2).ceil();
    return (stopCount * 0.6).ceil().clamp(3, stopCount);
  }
}

/// Velger ruteskift ut fra postkoder i PDF (stopp eller ≥4 treff i samme område).
class RouteShiftResolver {
  RouteShiftResolver._();

  static const int minPostalCodesPerRegion = 4;

  static bool _isHubPostal(String code) => PostalCodeRegistry.isHubPostalCode(code);

  static Future<RoutePostalAnalysis> analyzePdfText(String? pdfText) async {
    await PostalCodeRegistry.ensureLoaded();
    if (pdfText == null || pdfText.trim().isEmpty) {
      return const RoutePostalAnalysis(
        postalCodes: [],
        regionCounts: {},
        dominantCount: 0,
      );
    }

    final regionCounts = <String, int>{};
    final codeSet = <String>{};
    String? firstStopRegion;

    String? regionForPostal(String? code, {String? placeHint}) {
      if (code == null || code.length != 4) return null;
      if (_isHubPostal(code)) return null;
      if (PostalCodeRegistry.isKnown(code)) codeSet.add(code);
      final sted = PostalCodeRegistry.lookupSted(code);
      var region = PostalRegionMapper.stedToRegion(sted);
      if (region == null && placeHint != null && placeHint.isNotEmpty) {
        region = PostalRegionMapper.stedToRegion(placeHint) ??
            PostalRegionMapper.regionFromFreeText(placeHint);
      }
      return region;
    }

    String? placeHintForStop(RoutePdfCustomer stop) {
      final hint = stop.addressHint ?? '';
      final m = RegExp(
        r'\b(\d{4})\s+([A-Za-zÆØÅæøå][A-Za-zÆØÅæøå\s.-]{1,35})',
      ).firstMatch(hint);
      if (m != null) return m.group(2)?.trim();
      if (stop.postalCode != null) {
        return PostalCodeRegistry.lookupSted(stop.postalCode!);
      }
      return null;
    }

    String? regionForStop(RoutePdfCustomer stop) {
      final fromPostal = regionForPostal(
        stop.postalCode,
        placeHint: placeHintForStop(stop),
      );
      if (fromPostal != null) return fromPostal;

      final paren = RegExp(r'\(([^)]+)\)').firstMatch(stop.name);
      if (paren != null) {
        final place = paren.group(1)!.trim();
        final r = PostalRegionMapper.stedToRegion(place) ??
            PostalRegionMapper.regionFromFreeText(place);
        if (r != null) return r;
      }

      if (stop.addressHint != null && stop.addressHint!.isNotEmpty) {
        final r = PostalRegionMapper.regionFromFreeText(stop.addressHint);
        if (r != null) return r;
      }
      return PostalRegionMapper.regionFromFreeText(stop.name);
    }

    void countRegion(String? region) {
      if (region == null) return;
      regionCounts[region] = (regionCounts[region] ?? 0) + 1;
    }

    final stops = RoutePdfTextService.parseCustomers(pdfText);
    final stopCount = stops.length;
    if (stops.isNotEmpty) {
      for (final stop in stops) {
        final region = regionForStop(stop);
        firstStopRegion ??= region;
        countRegion(region);
      }
    } else {
      for (final code in RoutePdfTextService.extractPostalCodes(pdfText)) {
        countRegion(regionForPostal(code));
      }
      final fromText = PostalRegionMapper.regionFromFreeText(pdfText);
      countRegion(fromText);
    }

    var dominant = _pickDominantRegion(
      regionCounts,
      deliveryStopCount: stopCount,
      firstStopRegion: firstStopRegion,
    );

    final codes = codeSet.toList()..sort();
    final max = dominant == null ? 0 : (regionCounts[dominant] ?? 0);

    return RoutePostalAnalysis(
      postalCodes: codes,
      regionCounts: regionCounts,
      dominantRegion: dominant,
      dominantCount: max,
      deliveryStopCount: stopCount,
      firstStopRegion: firstStopRegion,
    );
  }

  static String? _pickDominantRegion(
    Map<String, int> regionCounts, {
    required int deliveryStopCount,
    String? firstStopRegion,
  }) {
    if (regionCounts.isEmpty) return null;

    final sorted = regionCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.first;
    final second = sorted.length > 1 ? sorted[1].value : 0;

    if (deliveryStopCount >= 1) {
      if (top.value > second) return top.key;
      if (top.value == second && top.value > 0) {
        if (firstStopRegion != null &&
            regionCounts.containsKey(firstStopRegion)) {
          return firstStopRegion;
        }
        return top.key;
      }
      if (deliveryStopCount == 1 && top.value >= 1) return top.key;
    }

    if (top.value >= minPostalCodesPerRegion) return top.key;
    if (deliveryStopCount == 0 && top.value >= 2 && top.value > second) {
      return top.key;
    }
    if (deliveryStopCount == 0 && top.value >= 1 && sorted.length == 1) {
      return top.key;
    }
    return null;
  }

  static FleetShiftDefinition? pickShiftForRegion({
    required List<FleetShiftDefinition> shifts,
    required String region,
    DateTime? routeStartAt,
    String? timeBand,
  }) {
    final ops = FleetShiftFilters.forRouteAssignment(shifts);
    if (ops.isEmpty) return null;

    final band = timeBand ?? RouteTimeBand.fromDateTime(routeStartAt);
    final regionNorm = _norm(region);

    for (final s in ops) {
      if (_norm(s.regionGroup ?? '') != regionNorm) continue;
      if (s.timeBand == band) return s;
    }
    for (final s in ops) {
      if (_norm(s.regionGroup ?? '') != regionNorm) continue;
      final name = s.name.toLowerCase();
      if (band == 'dag' && name.startsWith('dagrute')) return s;
      if (band == 'kveld' && name.startsWith('kvelds')) return s;
    }
    for (final s in ops) {
      if (_norm(s.regionGroup ?? '') == regionNorm) return s;
    }
    return null;
  }

  static ({DateTime? start, String band}) _inferScheduleFromPdf(
    String? pdfText,
    DateTime? routeDate,
    DateTime? routeStartAt,
  ) {
    final day = routeDate ?? DateTime.now();
    final local = DateTime(day.year, day.month, day.day);
    final stops = pdfText == null || pdfText.trim().isEmpty
        ? const <RoutePdfCustomer>[]
        : RoutePdfTextService.parseCustomers(pdfText);
    final start = routeStartAt ?? _routeStartFromPdf(pdfText, local);
    final band = RouteTimeBand.inferFromStops(stops, fallbackStart: start);
    return (start: start, band: band);
  }

  static Future<FleetShiftDefinition?> resolveFromPdfText({
    required String? pdfText,
    required List<FleetShiftDefinition> shifts,
    DateTime? routeStartAt,
    DateTime? routeDate,
    bool bestEffort = false,
  }) async {
    final analysis = await analyzePdfText(pdfText);
    final region =
        bestEffort ? analysis.bestEffortRegion : analysis.dominantRegion;
    if (region == null) return null;
    if (!bestEffort && !analysis.hasConfidentRegion) return null;
    final sched = _inferScheduleFromPdf(pdfText, routeDate, routeStartAt);
    return pickShiftForRegion(
      shifts: shifts,
      region: region,
      routeStartAt: sched.start,
      timeBand: sched.band,
    );
  }

  static DateTime? _routeStartFromPdf(String? pdfText, DateTime? routeDate) {
    if (pdfText == null || pdfText.trim().isEmpty) return null;
    final day = routeDate ?? DateTime.now();
    final local = DateTime(day.year, day.month, day.day);
    return RoutePdfTextService.parseEarliestStopStartTime(pdfText, routeDate: local);
  }

  /// Sterk gjetning for kladd/publisering — bruker beste område + tid fra PDF.
  static Future<FleetShiftDefinition?> resolveBestFromPdfText({
    required String? pdfText,
    required List<FleetShiftDefinition> shifts,
    DateTime? routeStartAt,
    DateTime? routeDate,
    String? title,
    String? notes,
  }) async {
    final sched = _inferScheduleFromPdf(pdfText, routeDate, routeStartAt);
    final fromPdf = await resolveFromPdfText(
      pdfText: pdfText,
      shifts: shifts,
      routeStartAt: sched.start,
      routeDate: routeDate,
      bestEffort: true,
    );
    if (fromPdf != null) return fromPdf;

    final metaRegion = PostalRegionMapper.regionFromShareMetadata(
      title: title,
      notes: notes,
    );
    if (metaRegion != null) {
      return pickShiftForRegion(
        shifts: shifts,
        region: metaRegion,
        routeStartAt: sched.start,
        timeBand: sched.band,
      );
    }

    if (pdfText != null && pdfText.trim().isNotEmpty) {
      final fallbackRegion = PostalRegionMapper.regionFromFreeText(pdfText);
      if (fallbackRegion != null) {
        return pickShiftForRegion(
          shifts: shifts,
          region: fallbackRegion,
          routeStartAt: sched.start,
          timeBand: sched.band,
        );
      }
    }
    return null;
  }

  static bool pdfTextUsableForShift(String? text) {
    if (text == null || text.trim().isEmpty) return false;
    if (RoutePdfTextService.parseCustomers(text).isNotEmpty) return true;
    final codes = RoutePdfTextService.extractPostalCodes(text)
        .where((c) => !_isHubPostal(c))
        .toList();
    if (codes.length >= 2) return true;
    if (PostalRegionMapper.regionFromFreeText(text) != null) return true;
    return false;
  }

  /// Rekkefølge: eksisterende shift → tittel → postkoder. Ingen gjetting ved tvil.
  static Future<String?> guessShiftId({
    required PartnerRouteShare share,
    required List<FleetShiftDefinition> shifts,
  }) async {
    final ops = FleetShiftFilters.forRouteAssignment(shifts);
    if (ops.isEmpty) return null;

    if (share.shiftId != null && share.shiftId!.isNotEmpty) {
      FleetShiftDefinition? current;
      for (final s in shifts) {
        if (s.id == share.shiftId) {
          current = s;
          break;
        }
      }
      if (current != null &&
          !FleetShiftFilters.isGeilo(current) &&
          ops.any((s) => s.id == share.shiftId)) {
        return share.shiftId;
      }
    }

    final title = (share.title ?? '').toLowerCase();
    for (final s in ops) {
      final name = s.name.toLowerCase();
      if (name.length < 8) continue;
      if (title.contains(name)) return s.id;
    }

    final best = await resolveBestFromPdfText(
      pdfText: share.pdfSearchText,
      shifts: ops,
      routeStartAt: share.routeStartAt,
      routeDate: share.shareDate,
      title: share.title,
      notes: share.notes,
    );
    return best?.id;
  }

  /// Beste skift for kladd: PDF → lagret shift (ikke Geilo) → best-effort område/tid.
  static Future<String?> resolveShiftIdForStagedShare({
    required PartnerRouteShare share,
    required List<FleetShiftDefinition> allShifts,
    String? pdfText,
  }) async {
    final routeShifts = FleetShiftFilters.forRouteAssignment(allShifts);
    if (routeShifts.isEmpty) return null;

    final text = (pdfText ?? share.pdfSearchText)?.trim();
    final shareWithText = (text != null && text.isNotEmpty && text != share.pdfSearchText)
        ? PartnerRouteShare(
            id: share.id,
            partnerId: share.partnerId,
            companyId: share.companyId,
            title: share.title,
            pdfStoragePath: share.pdfStoragePath,
            shareDate: share.shareDate,
            isDailyShare: share.isDailyShare,
            notes: share.notes,
            ackStatus: share.ackStatus,
            ackAt: share.ackAt,
            ackBy: share.ackBy,
            ackComment: share.ackComment,
            shiftId: share.shiftId,
            partnerVehicleId: share.partnerVehicleId,
            routeStartAt: share.routeStartAt,
            dispatchStatus: share.dispatchStatus,
            pdfSearchText: text,
            customerCount: share.customerCount,
            createdAt: share.createdAt,
          )
        : share;

    final guessed = await guessShiftId(share: shareWithText, shifts: allShifts);
    if (guessed != null && guessed.isNotEmpty) return guessed;

    final best = await resolveBestFromPdfText(
      pdfText: text,
      shifts: routeShifts,
      routeStartAt: share.routeStartAt,
      routeDate: share.shareDate,
      title: share.title,
      notes: share.notes,
    );
    return best?.id;
  }

  /// Henter PDF-tekst fra lagring; laster full PDF på nytt hvis cache mangler stopp/postnr.
  static Future<String?> loadPdfTextForShare(PartnerRouteShare share) async {
    final cached = share.pdfSearchText?.trim();
    if (cached != null && cached.isNotEmpty && pdfTextUsableForShift(cached)) {
      return cached;
    }

    final bytes = await PartnerService.downloadRoutePdfBytes(share.pdfStoragePath);
    if (bytes == null || bytes.isEmpty) {
      return cached != null && cached.isNotEmpty ? cached : null;
    }

    var text = RoutePdfTextService.extractFullText(bytes);
    if (text.isEmpty) {
      text = RoutePdfTextService.extractHeaderText(bytes);
    }
    if (text.isEmpty) {
      return cached != null && cached.isNotEmpty ? cached : null;
    }

    if (text != cached) {
      await PartnerService.saveRoutePdfSearchText(share.id, text);
    }
    return text;
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll('æ', 'ae').replaceAll('ø', 'o').replaceAll('å', 'aa');
}
