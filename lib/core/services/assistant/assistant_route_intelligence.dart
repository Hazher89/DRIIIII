import 'package:intl/intl.dart';

import '../../routing/app_paths.dart';
import '../partner/mavi_unit_codes.dart';
import '../partner/partner_service.dart';
import '../partner/postal_region_mapper.dart';
import '../supabase_service.dart';
import '../../../models/partner/partner_route_dispatch_history.dart';
import 'assistant_access_policy.dart';
import 'assistant_corpus.dart';
import 'assistant_memory_service.dart';

/// Live rute-svar for alle biler (MAVI-nr, reg.nr, partner, sjåførnavn).
class AssistantRouteIntelligence {
  AssistantRouteIntelligence._();

  static final _maviRe = RegExp(
    r'(?:\bno[_]?o[_]?m0*(\d{1,5})\b|\bm\s*0*(\d{1,5})\b)',
    caseSensitive: false,
  );

  /// Norsk skilt / reg.nr-lignende token (EL12345, AB12345, …).
  static final _plateRe = RegExp(
    r'\b([A-ZÆØÅ]{1,3}\s?\d{2,5})\b',
    caseSensitive: false,
  );

  static String? extractMaviCode(String query) {
    final m = _maviRe.firstMatch(query.trim());
    if (m == null) return null;
    final n = int.tryParse(m.group(1) ?? m.group(2) ?? '');
    if (n == null) return null;
    return MaviUnitCodes.normalize('M$n');
  }

  static bool looksLikeRouteQuery(String query) {
    final q = query.toLowerCase();
    final hasVehicleHint = extractMaviCode(query) != null ||
        _plateRe.hasMatch(query) ||
        q.contains('bil') ||
        q.contains('reg.nr') ||
        q.contains('regnr') ||
        q.contains('skilt');
    if (!hasVehicleHint && !_hasLooseVehicleContext(q)) return false;
    return q.contains('rute') ||
        q.contains('kjort') ||
        q.contains('kjørt') ||
        q.contains('kunde') ||
        q.contains('omrade') ||
        q.contains('område') ||
        q.contains('endre') ||
        q.contains('endring') ||
        q.contains('oppdatert') ||
        q.contains('sendt') ||
        q.contains('hvor') ||
        q.contains('hvor mange') ||
        q.contains('siste') ||
        q.contains('uke') ||
        q.contains('flate') ||
        q.contains('partner') ||
        q.contains('bil');
  }

  static bool _hasLooseVehicleContext(String q) =>
      q.contains('partner') || q.contains('sjåfør') || q.contains('sjafor');

  /// Svarer med live data for valgfri bil (ikke bare M-nummer).
  static Future<String?> tryAnswer(String query) async {
    if (!looksLikeRouteQuery(query) && extractMaviCode(query) == null) {
      return null;
    }

    final viewer = await SupabaseService.fetchCurrentUserProfile();
    if (viewer == null || viewer.companyId == null) {
      return 'Du må være innlogget for at jeg skal hente rutedata.';
    }
    if (!await AssistantAccessPolicy.canViewFleetOps(viewer)) {
      return 'Beklager — du har ikke tilgang til rute-/flåtedata.';
    }

    final companyId = viewer.companyId!;
    final range = _parseRange(query);
    final rows = await PartnerService.fetchRouteDispatchHistory(
      companyId: companyId,
      fromDate: range.from,
      toDate: range.to,
    );
    final fleet = await PartnerService.fetchCompanyFleet(companyId);

    final match = _resolveVehicle(query, rows, fleet);
    if (match == null) {
      if (extractMaviCode(query) != null || _plateRe.hasMatch(query)) {
        return 'Jeg fant ingen bil som matcher i rutehistorikken for perioden. '
            'Prøv MAVI-nr (M09), reg.nr eller partnernavn — eller et lengre tidsrom.';
      }
      return null;
    }

    final forVehicle = rows
        .where((r) => match.matchesRow(r))
        .where((r) =>
            r.dispatchStatus == 'sent' || r.dispatchStatus == 'registered')
        .toList()
      ..sort((a, b) {
        final c = b.shareDate.compareTo(a.shareDate);
        if (c != 0) return c;
        return (b.sentAt ?? b.shareDate).compareTo(a.sentAt ?? a.shareDate);
      });

    final label = match.label;
    final df = DateFormat('dd.MM.yyyy');
    final periodLabel = '${df.format(range.from)} – ${df.format(range.to)}';

    if (forVehicle.isEmpty) {
      return 'Jeg fant ingen sendte ruter for $label i perioden $periodLabel. '
          'Sjekk Partner → Rutehistorikk, eller spør for «siste måned».';
    }

    final summary = _summarize(forVehicle);
    final intent = _intent(query);
    final answer = switch (intent) {
      _RouteIntent.areas => _answerAreas(label, periodLabel, summary),
      _RouteIntent.customers => _answerCustomers(label, periodLabel, summary),
      _RouteIntent.changes => _answerChanges(label, periodLabel, summary),
      _RouteIntent.overview => _answerOverview(label, periodLabel, summary),
    };

    await AssistantMemoryService.remember(
      companyId: companyId,
      kind: 'route_fact',
      content: answer,
      subjectKey: 'vehicle:${match.subjectKey}',
      visibility: 'company',
      sourceQuery: query,
    );
    return answer;
  }

  static _VehicleMatch? _resolveVehicle(
    String query,
    List<PartnerRouteDispatchHistoryRow> rows,
    List<FleetPartnerVehicleRow> fleet,
  ) {
    final q = query.toLowerCase();
    final mavi = extractMaviCode(query);

    // 1) Eksplisitt MAVI-nr
    if (mavi != null) {
      return _VehicleMatch(
        label: MaviUnitCodes.compactLabel(mavi),
        subjectKey: mavi,
        matchesRow: (r) => _normUnit(r.unitCode) == mavi,
      );
    }

    // 2) Reg.nr i spørsmål
    final plateMatch = _plateRe.firstMatch(query);
    if (plateMatch != null) {
      final plate = _normPlate(plateMatch.group(1)!);
      if (plate.length >= 5) {
        for (final row in fleet) {
          if (_normPlate(row.vehicle.registrationNumber) == plate) {
            final unit = MaviUnitCodes.normalize(row.vehicle.unitCode);
            final label = unit.isNotEmpty
                ? '${MaviUnitCodes.compactLabel(unit)} · ${row.vehicle.registrationNumber}'
                : row.vehicle.registrationNumber;
            return _VehicleMatch(
              label: label,
              subjectKey: plate,
              matchesRow: (r) =>
                  _normPlate(r.registrationNumber ?? '') == plate ||
                  (unit.isNotEmpty && _normUnit(r.unitCode) == unit),
            );
          }
        }
        // Historikk kan ha reg.nr uten at flåten matcher.
        final hist = rows.where(
          (r) => _normPlate(r.registrationNumber ?? '') == plate,
        );
        if (hist.isNotEmpty) {
          return _VehicleMatch(
            label: hist.first.registrationNumber ?? plate,
            subjectKey: plate,
            matchesRow: (r) => _normPlate(r.registrationNumber ?? '') == plate,
          );
        }
      }
    }

    // 3) Partnernavn / sjåførnavn / unit i flåte
    _VehicleMatch? best;
    var bestScore = 0;
    for (final row in fleet) {
      final v = row.vehicle;
      final unit = MaviUnitCodes.normalize(v.unitCode);
      final compact = unit.isNotEmpty ? MaviUnitCodes.compactLabel(unit) : '';
      final partner = row.partner.name.trim().toLowerCase();
      final driver = (v.driverName ?? '').trim().toLowerCase();
      final plate = _normPlate(v.registrationNumber);
      var score = 0;
      if (compact.isNotEmpty && q.contains(compact.toLowerCase())) score += 30;
      if (unit.isNotEmpty && q.contains(unit.toLowerCase())) score += 25;
      if (partner.length >= 3 && q.contains(partner)) score += partner.length;
      if (driver.length >= 3 && q.contains(driver)) score += driver.length + 5;
      if (plate.length >= 5 && q.contains(plate.toLowerCase())) score += 40;
      if (score > bestScore) {
        bestScore = score;
        final label = [
          if (compact.isNotEmpty) compact,
          if (v.registrationNumber.trim().isNotEmpty &&
              v.registrationNumber != MaviUnitCodes.regNrPlaceholder)
            v.registrationNumber.trim(),
          if (partner.isNotEmpty) row.partner.name.trim(),
        ].join(' · ');
        best = _VehicleMatch(
          label: label.isEmpty ? 'Bil' : label,
          subjectKey: unit.isNotEmpty ? unit : plate,
          matchesRow: (r) {
            if (unit.isNotEmpty && _normUnit(r.unitCode) == unit) return true;
            if (plate.length >= 5 &&
                _normPlate(r.registrationNumber ?? '') == plate) {
              return true;
            }
            final pn = (r.partnerName ?? '').trim().toLowerCase();
            return partner.length >= 3 && pn == partner;
          },
        );
      }
    }

    if (bestScore >= 8) return best;
    return null;
  }

  static String _normUnit(String? raw) => MaviUnitCodes.normalize(raw ?? '');

  static String _normPlate(String raw) =>
      raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  static ({DateTime from, DateTime to}) _parseRange(String query) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final q = query.toLowerCase();

    if (q.contains('i dag') || q.contains('idag')) {
      return (from: today, to: today);
    }
    if (q.contains('i går') || q.contains('igar') || q.contains('i gar')) {
      final y = today.subtract(const Duration(days: 1));
      return (from: y, to: y);
    }
    if (q.contains('måned') || q.contains('maned') || q.contains('30 dag')) {
      return (from: today.subtract(const Duration(days: 30)), to: today);
    }
    if (q.contains('14 dag') || q.contains('to uker')) {
      return (from: today.subtract(const Duration(days: 14)), to: today);
    }
    // «siste uke» / «denne uken» / default for «i det siste»
    if (q.contains('uke') ||
        q.contains('siste') ||
        q.contains('nylig') ||
        q.contains('det siste')) {
      return (from: today.subtract(const Duration(days: 6)), to: today);
    }
    return (from: today.subtract(const Duration(days: 6)), to: today);
  }

  static _RouteIntent _intent(String query) {
    final q = query.toLowerCase();
    if (q.contains('endre') ||
        q.contains('endring') ||
        q.contains('oppdatert') ||
        q.contains('ny rute') ||
        q.contains('sendt på nytt') ||
        q.contains('republiser')) {
      return _RouteIntent.changes;
    }
    if (q.contains('kunde')) return _RouteIntent.customers;
    if (q.contains('hvor') ||
        q.contains('område') ||
        q.contains('omrade') ||
        q.contains('kjørt') ||
        q.contains('kjort') ||
        q.contains('region')) {
      return _RouteIntent.areas;
    }
    return _RouteIntent.overview;
  }

  static _UnitRouteSummary _summarize(List<PartnerRouteDispatchHistoryRow> rows) {
    final byDay = <String, List<PartnerRouteDispatchHistoryRow>>{};
    for (final r in rows) {
      final key =
          '${r.shareDate.year}-${r.shareDate.month}-${r.shareDate.day}';
      byDay.putIfAbsent(key, () => []).add(r);
    }

    var customers = 0;
    var changeEvents = 0;
    final areas = <String, int>{};
    final dayLines = <String>[];
    final df = DateFormat('dd.MM');

    for (final entry in byDay.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key))) {
      final dayRows = entry.value
        ..sort((a, b) =>
            (b.sentAt ?? b.shareDate).compareTo(a.sentAt ?? a.shareDate));
      // Nyeste rute den dagen teller for kunder/område; ekstra send = endringer.
      final latest = dayRows.first;
      final cust = latest.customerCount ?? 0;
      customers += cust;
      if (dayRows.length > 1) {
        changeEvents += dayRows.length - 1;
      }

      final area = _areaFor(latest);
      areas[area] = (areas[area] ?? 0) + 1;

      final partner = (latest.partnerName ?? '').trim();
      dayLines.add(
        '• ${df.format(latest.shareDate)}: $area'
        '${cust > 0 ? ' · $cust kunder' : ''}'
        '${dayRows.length > 1 ? ' · ${dayRows.length} sendinger (endret)' : ''}'
        '${partner.isNotEmpty ? ' · $partner' : ''}',
      );
    }

    return _UnitRouteSummary(
      routeDays: byDay.length,
      totalDispatches: rows.length,
      customers: customers,
      changeEvents: changeEvents,
      areas: areas,
      dayLines: dayLines,
      partnerName: rows
          .map((r) => (r.partnerName ?? '').trim())
          .where((s) => s.isNotEmpty)
          .fold<String?>(null, (prev, e) => prev ?? e),
    );
  }

  static String _areaFor(PartnerRouteDispatchHistoryRow r) {
    final fromMeta = PostalRegionMapper.regionFromShareMetadata(
      title: r.title,
      notes: r.shiftName,
    );
    if (fromMeta != null && fromMeta.trim().isNotEmpty) return fromMeta.trim();

    final fromShift = PostalRegionMapper.regionFromFreeText(r.shiftName);
    if (fromShift != null) return fromShift;

    final fromTitle = PostalRegionMapper.regionFromFreeText(r.title);
    if (fromTitle != null) return fromTitle;

    final shift = (r.shiftName ?? '').trim();
    if (shift.isNotEmpty) return shift;
    final title = (r.title ?? '').trim();
    if (title.isNotEmpty) return title;
    return 'Ukjent område';
  }

  static String _answerAreas(
    String label,
    String period,
    _UnitRouteSummary s,
  ) {
    final buf = StringBuffer();
    buf.writeln('$label har kjørt i perioden $period:');
    buf.writeln();
    if (s.areas.isEmpty) {
      buf.writeln('Ingen områder fant jeg i rutetitlene/skiftene.');
    } else {
      final sorted = s.areas.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sorted) {
        buf.writeln(
          '• ${e.key}: ${e.value} ${e.value == 1 ? 'dag' : 'dager'}',
        );
      }
    }
    buf.writeln();
    buf.writeln('Detaljer:');
    for (final line in s.dayLines.take(10)) {
      buf.writeln(line);
    }
    if (s.dayLines.length > 10) {
      buf.writeln('… +${s.dayLines.length - 10} dager til');
    }
    return buf.toString().trim();
  }

  static String _answerCustomers(
    String label,
    String period,
    _UnitRouteSummary s,
  ) {
    final buf = StringBuffer();
    buf.writeln(
      '$label har hatt ${s.customers} kunder fordelt på ${s.routeDays} '
      'rutedager i perioden $period '
      '(${s.totalDispatches} sendinger totalt).',
    );
    if (s.partnerName != null) {
      buf.writeln('Partner: ${s.partnerName}.');
    }
    buf.writeln();
    if (s.areas.isNotEmpty) {
      buf.writeln('Fordeling per område:');
      final sorted = s.areas.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sorted.take(8)) {
        buf.writeln('• ${e.key}: ${e.value} dager');
      }
    }
    buf.writeln();
    buf.writeln('Per dag:');
    for (final line in s.dayLines.take(10)) {
      buf.writeln(line);
    }
    return buf.toString().trim();
  }

  static String _answerChanges(
    String label,
    String period,
    _UnitRouteSummary s,
  ) {
    final buf = StringBuffer();
    if (s.changeEvents <= 0) {
      buf.writeln(
        'For $label i perioden $period fant jeg ingen ekstra ruteendringer '
        '(én sending per rutedag · ${s.routeDays} dager).',
      );
    } else {
      buf.writeln(
        'For $label i perioden $period ble ruten endret/sendt på nytt '
        '${s.changeEvents} ${s.changeEvents == 1 ? 'gang' : 'ganger'} '
        '(${s.totalDispatches} sendinger fordelt på ${s.routeDays} rutedager).',
      );
    }
    buf.writeln();
    buf.writeln('Dager med flere sendinger / endringer:');
    final changed = s.dayLines.where((l) => l.contains('endret')).toList();
    if (changed.isEmpty) {
      buf.writeln('• Ingen dager med flere sendinger.');
    } else {
      for (final line in changed.take(12)) {
        buf.writeln(line);
      }
    }
    return buf.toString().trim();
  }

  static String _answerOverview(
    String label,
    String period,
    _UnitRouteSummary s,
  ) {
    final topAreas = s.areas.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final areaText = topAreas.isEmpty
        ? 'ukjent område'
        : topAreas.take(3).map((e) => e.key).join(', ');

    final buf = StringBuffer();
    buf.writeln(
      '$label · $period: ${s.routeDays} rutedager · '
      '${s.customers} kunder · ${s.changeEvents} ruteendringer.',
    );
    if (s.partnerName != null) buf.writeln('Partner: ${s.partnerName}.');
    buf.writeln('Områder: $areaText.');
    buf.writeln();
    for (final line in s.dayLines.take(8)) {
      buf.writeln(line);
    }
    if (s.dayLines.length > 8) {
      buf.writeln('… +${s.dayLines.length - 8} dager til');
    }
    buf.writeln();
    buf.writeln(
      'Du kan også spørre: «hvor har $label kjørt siste uke?», '
      '«hvor mange kunder har $label hatt?» eller '
      '«hvor mange ganger ble ruten endret på $label?»',
    );
    return buf.toString().trim();
  }

  static List<KnowledgeChunk> faqHints() => const [
        KnowledgeChunk(
          id: 'faq:route-live-mavi',
          source: KnowledgeSourceKind.help,
          title: 'Spør om ruter for alle biler',
          body:
              'Du kan spørre live om alle kjøretøy — ikke bare M-nummer:\n'
              '• «Hvor har M09 kjørt i det siste?»\n'
              '• «Hvor mange kunder har EL12345 hatt denne uken?»\n'
              '• «Hvor mange ganger ble ruten endret på partner X?»\n'
              '• «Oversikt for M62 siste måned»\n\n'
              'Svarene bygger på faktiske rutesendinger (område, kunder, endringer). '
              'Assistenten lærer av hver hendelse og husker fakta til senere.',
          routePath: AppPaths.partners,
          tags: [
            'm09',
            'm08',
            'm62',
            'rute',
            'kunder',
            'område',
            'endre rute',
            'mavi',
            'flåte',
            'reg.nr',
            'bil',
          ],
        ),
      ];
}

class _VehicleMatch {
  const _VehicleMatch({
    required this.label,
    required this.subjectKey,
    required this.matchesRow,
  });

  final String label;
  final String subjectKey;
  final bool Function(PartnerRouteDispatchHistoryRow row) matchesRow;
}

enum _RouteIntent { areas, customers, changes, overview }

class _UnitRouteSummary {
  final int routeDays;
  final int totalDispatches;
  final int customers;
  final int changeEvents;
  final Map<String, int> areas;
  final List<String> dayLines;
  final String? partnerName;

  const _UnitRouteSummary({
    required this.routeDays,
    required this.totalDispatches,
    required this.customers,
    required this.changeEvents,
    required this.areas,
    required this.dayLines,
    this.partnerName,
  });
}
