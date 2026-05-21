import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../sms/sms_phone_utils.dart';

/// Kunde fra MAVI-rute-PDF (Trip Overview / stopp).
class RoutePdfCustomer {
  final int sequence;
  final String name;
  final String phoneDisplay;
  final String phoneNormalizedKey;
  final String? freightUnit;
  final String? addressHint;
  /// Leveringsvindu fra PDF, f.eks. «08:00–13:00».
  final String? deliveryWindow;

  const RoutePdfCustomer({
    required this.sequence,
    required this.name,
    required this.phoneDisplay,
    required this.phoneNormalizedKey,
    this.freightUnit,
    this.addressHint,
    this.deliveryWindow,
  });
}

/// Dato/tid hentet fra MAVI-rute-PDF (Trip Overview / stopp-liste).
class RoutePdfSchedule {
  final DateTime routeDate;
  final DateTime? routeStartAt;

  const RoutePdfSchedule({
    required this.routeDate,
    this.routeStartAt,
  });
}

/// MAVI + Stowing Lane fra Trip Overview (første side).
class RoutePdfTripOverviewMeta {
  final String? maviCode;
  final String? stowingLane;

  const RoutePdfTripOverviewMeta({this.maviCode, this.stowingLane});
}

/// Ekstraherer og scorer PDF-tekst for smart rutesøk (klient-side).
class RoutePdfTextService {
  RoutePdfTextService._();

  static String extractFullText(Uint8List bytes) {
    try {
      final doc = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(doc);
      final text = extractor.extractText();
      doc.dispose();
      return _normalize(text);
    } catch (_) {
      return '';
    }
  }

  /// Leser `Start date 24.04.26` og starttid fra stopp (`24.04.2026 17:00:00`).
  static RoutePdfSchedule resolveSchedule(
    String text, {
    required DateTime fallbackDate,
  }) {
    final routeDate = parseRouteDate(text) ??
        DateTime(fallbackDate.year, fallbackDate.month, fallbackDate.day);
    final routeStartAt = parseRouteStartAt(text, routeDate: routeDate);
    return RoutePdfSchedule(routeDate: routeDate, routeStartAt: routeStartAt);
  }

  static RoutePdfSchedule resolveScheduleFromBytes(
    Uint8List bytes, {
    required DateTime fallbackDate,
  }) {
    return resolveSchedule(extractFullText(bytes), fallbackDate: fallbackDate);
  }

  static DateTime? parseRouteDate(String raw) {
    if (raw.trim().isEmpty) return null;
    final text = raw.replaceAll('\uFF3F', '_');

    final startDate = RegExp(
      r'Start\s+date\s+(\d{1,2})\.(\d{1,2})\.(\d{2,4})',
      caseSensitive: false,
    ).firstMatch(text);
    if (startDate != null) {
      return _dateFromParts(startDate.group(1)!, startDate.group(2)!, startDate.group(3)!);
    }

    final stopDateTime = RegExp(
      r'(\d{1,2})\.(\d{1,2})\.(\d{2,4})\s+\d{1,2}:\d{2}',
    ).firstMatch(text);
    if (stopDateTime != null) {
      return _dateFromParts(stopDateTime.group(1)!, stopDateTime.group(2)!, stopDateTime.group(3)!);
    }

    return null;
  }

  static DateTime? parseRouteStartAt(String raw, {DateTime? routeDate}) {
    if (raw.trim().isEmpty) return null;
    final text = raw.replaceAll('\uFF3F', '_');
    final match = RegExp(
      r'(\d{1,2})\.(\d{1,2})\.(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?',
    ).firstMatch(text);
    if (match == null) return null;

    final date = _dateFromParts(match.group(1)!, match.group(2)!, match.group(3)!);
    if (date == null) return null;
    final hour = int.tryParse(match.group(4)!);
    final minute = int.tryParse(match.group(5)!);
    if (hour == null || minute == null) return null;

    final base = routeDate ?? date;
    return DateTime(base.year, base.month, base.day, hour, minute);
  }

  static DateTime? _dateFromParts(String dayStr, String monthStr, String yearStr) {
    final day = int.tryParse(dayStr);
    final month = int.tryParse(monthStr);
    var year = int.tryParse(yearStr);
    if (day == null || month == null || year == null) return null;
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  static String _normalize(String raw) {
    return raw
        .replaceAll('\uFF3F', '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Henter kundenavn og telefon fra Elkjøp/MAVI Trip Overview-PDF.
  static List<RoutePdfCustomer> parseCustomers(String raw) {
    if (raw.trim().isEmpty) return const [];
    final fromOverview = _parseCustomersFromTripOverview(raw);
    if (fromOverview.isNotEmpty) return fromOverview;
    return _parseCustomersFromStopBlocks(raw);
  }

  static List<RoutePdfCustomer> parseCustomersFromBytes(Uint8List bytes) {
    return parseCustomers(extractFullText(bytes));
  }

  static List<RoutePdfCustomer> _parseCustomersFromTripOverview(String raw) {
    final flat = raw.replaceAll('\uFF3F', '_').replaceAll(RegExp(r'[\r\n]+'), ' ');
    final re = RegExp(
      r'(\d+)\s+(\d{8,12})\s+(.+?),\s*\+47\s*\(?(\d{8})\)?',
      caseSensitive: false,
    );
    final out = <RoutePdfCustomer>[];
    final seenSeq = <int>{};
    final matches = re.allMatches(flat).toList();
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final seq = int.tryParse(m.group(1)!);
      if (seq == null || !seenSeq.add(seq)) continue;
      final phoneRaw = m.group(4)!;
      final norm = normalizePhoneNo(phoneRaw);
      if (norm == null) continue;
      final rest = m.group(3)!.trim();
      final tailEnd = i + 1 < matches.length ? matches[i + 1].start : flat.length;
      final tail = flat.substring(m.end, tailEnd);
      out.add(
        RoutePdfCustomer(
          sequence: seq,
          name: _customerNameFromRest(rest),
          phoneDisplay: displayPhoneNo(norm),
          phoneNormalizedKey: norm,
          freightUnit: m.group(2),
          addressHint: rest.contains(',') ? rest : null,
          deliveryWindow: _extractDeliveryWindowFromSnippet(tail),
        ),
      );
    }
    out.sort((a, b) => a.sequence.compareTo(b.sequence));
    return out;
  }

  static List<RoutePdfCustomer> _parseCustomersFromStopBlocks(String raw) {
    final text = raw.replaceAll('\uFF3F', '_');
    final out = <RoutePdfCustomer>[];
    final seenSeq = <int>{};
    final stopRe = RegExp(
      r'Stop\s*#\s*Customer[^\d]*(\d+)\s+(.+?)\s+(\d{1,2}\.\d{1,2}\.\d{2,4})\s+(\d{1,2}:\d{2})(?::\d{2})?\s+(\d{1,2}\.\d{1,2}\.\d{2,4})\s+(\d{1,2}:\d{2})(?::\d{2})?',
      caseSensitive: false,
      dotAll: true,
    );
    for (final m in stopRe.allMatches(text)) {
      final seq = int.tryParse(m.group(1)!);
      if (seq == null || !seenSeq.add(seq)) continue;
      final blockStart = m.start;
      final blockEnd = (blockStart + 1200).clamp(0, text.length);
      final block = text.substring(blockStart, blockEnd);
      final phoneM = RegExp(r'\+\s*47\s*\(?(\d{8})\)?', caseSensitive: false).firstMatch(block);
      if (phoneM == null) continue;
      final norm = normalizePhoneNo(phoneM.group(1)!);
      if (norm == null) continue;
      final rest = m.group(2)!.trim();
      final startT = _shortTime(m.group(4)!);
      final endT = _shortTime(m.group(6)!);
      out.add(
        RoutePdfCustomer(
          sequence: seq,
          name: _customerNameFromRest(rest),
          phoneDisplay: displayPhoneNo(norm),
          phoneNormalizedKey: norm,
          addressHint: rest.contains(',') ? rest : null,
          deliveryWindow: startT != null && endT != null ? '$startT–$endT' : null,
        ),
      );
    }
    out.sort((a, b) => a.sequence.compareTo(b.sequence));
    return out;
  }

  /// Finner «08:00 13:00» etter telefon i Trip Overview-raden.
  static String? _extractDeliveryWindowFromSnippet(String snippet) {
    final times = RegExp(r'\b(\d{1,2}:\d{2})\b')
        .allMatches(snippet)
        .map((m) => m.group(1)!)
        .toList();
    if (times.length >= 2) {
      final start = _shortTime(times[times.length - 2]);
      final end = _shortTime(times.last);
      if (start != null && end != null) return '$start–$end';
    }
    if (times.length == 1) return _shortTime(times.first);
    return null;
  }

  static String? _shortTime(String t) {
    final parts = t.split(':');
    if (parts.length < 2) return t;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return t;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  static String _customerNameFromRest(String rest) {
    final comma = rest.indexOf(',');
    if (comma > 0) return rest.substring(0, comma).trim();
    final digits = RegExp(r'\s\d{4}\s').firstMatch(rest);
    if (digits != null && digits.start > 0) {
      return rest.substring(0, digits.start).trim();
    }
    return rest.trim();
  }

  /// Score 0–100: høyere = bedre treff.
  static int scoreMatch({
    required String query,
    required String pdfText,
    String? title,
    String? fileName,
    String? maviCode,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return 0;
    final text = pdfText.toLowerCase();
    final tit = (title ?? '').toLowerCase();
    final file = (fileName ?? '').toLowerCase();
    final mavi = (maviCode ?? '').toLowerCase();

    var score = 0;
    if (text.contains(q)) score += 40;
    if (tit.contains(q)) score += 25;
    if (file.contains(q)) score += 20;
    if (mavi.contains(q)) score += 30;

    final tokens = q.split(RegExp(r'\s+')).where((t) => t.length >= 2);
    var tokenHits = 0;
    for (final t in tokens) {
      if (text.contains(t)) tokenHits++;
      if (tit.contains(t)) tokenHits++;
    }
    if (tokens.isNotEmpty) {
      score += ((tokenHits / (tokens.length * 2)) * 35).round();
    }

    if (q.length >= 4 && !text.contains(q) && tokenHits == 0) {
      return 0;
    }
    return score.clamp(0, 100);
  }

  static String snippet(String text, String query, {int radius = 60}) {
    if (text.isEmpty) return '';
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return text.length > 120 ? '${text.substring(0, 120)}…' : text;
    }
    final lower = text.toLowerCase();
    final idx = lower.indexOf(q);
    if (idx < 0) {
      for (final part in q.split(RegExp(r'\s+'))) {
        if (part.length < 2) continue;
        final i = lower.indexOf(part);
        if (i >= 0) return _around(text, i, radius);
      }
      return text.length > 140 ? '${text.substring(0, 140)}…' : text;
    }
    return _around(text, idx, radius);
  }

  static String _around(String text, int idx, int radius) {
    final start = (idx - radius).clamp(0, text.length);
    final end = (idx + radius).clamp(0, text.length);
    var s = text.substring(start, end);
    if (start > 0) s = '…$s';
    if (end < text.length) s = '$s…';
    return s;
  }

  /// Normaliserer MAVI-kode fra PDF-tekst for oppslag mot flåteliste.
  static String normalizeUnitCodeForMatch(String raw) {
    final s = raw.trim().toUpperCase();
    if (s.isEmpty) return '';
    final noOm = RegExp(r'NO\s*[_-]?\s*O\s*[_-]?\s*M(\d{1,5})\b', caseSensitive: false).firstMatch(s);
    if (noOm != null) {
      final n = int.tryParse(noOm.group(1)!);
      if (n != null) return 'M$n';
    }
    final mDigits = RegExp(r'\bM(\d{1,5})\b', caseSensitive: false).firstMatch(s);
    if (mDigits != null) {
      final n = int.tryParse(mDigits.group(1)!);
      if (n != null) return 'M$n';
    }
    return s.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  /// Enkelt treff i rå PDF-tekst (brukes internt og for søk).
  static String? parseResourceId(String raw) {
    final ranked = _rankResourceIdCandidates(raw);
    if (ranked.isEmpty) return null;
    return ranked.first.code;
  }

  /// Stowing Lane fra PDF (f.eks. 17, 17B, 1A — samme sjåfør kan ha flere).
  static String? parseStowingLane(String raw) {
    if (raw.trim().isEmpty) return null;
    final text = raw.replaceAll('\uFF3F', '_');
    final m = RegExp(
      r'Stowing\s+Lane\s+(\d{1,3}\s*[A-Za-z]?)',
      caseSensitive: false,
    ).firstMatch(text);
    if (m == null) return null;
    return m.group(1)!.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  }

  static String? parseStowingLaneFromNotes(String? notes) {
    if (notes == null || notes.trim().isEmpty) return null;
    final m = RegExp(
      r'Stowing\s+Lane:\s*(\d{1,3}\s*[A-Za-z]?)',
      caseSensitive: false,
    ).firstMatch(notes);
    if (m == null) return null;
    return m.group(1)!.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  }

  static String? normalizeStowingLane(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final fromText = parseStowingLane(raw);
    if (fromText != null) return fromText;
    final t = raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^\d{1,3}[A-Z]?$').hasMatch(t)) return t;
    return null;
  }

  static String composeRouteNotes({String? stowingLane, String? userNote}) {
    final parts = <String>[];
    final lane = normalizeStowingLane(stowingLane);
    if (lane != null && lane.isNotEmpty) {
      parts.add('Stowing Lane: $lane');
    }
    final extra = userNote?.trim() ?? '';
    if (extra.isNotEmpty) {
      final lower = extra.toLowerCase();
      if (!lower.startsWith('stowing lane:')) {
        parts.add(extra);
      }
    }
    return parts.join('\n');
  }

  static RoutePdfTripOverviewMeta extractTripOverviewMeta(Uint8List bytes) {
    final text = extractFullText(bytes);
    return RoutePdfTripOverviewMeta(
      maviCode: parseResourceId(text),
      stowingLane: parseStowingLane(text),
    );
  }

  static RoutePdfTripOverviewMeta extractTripOverviewMetaFromText(String text) {
    return RoutePdfTripOverviewMeta(
      maviCode: parseResourceId(text),
      stowingLane: parseStowingLane(text),
    );
  }

  /// Henter MAVI Resource ID kun fra PDF-innhold (aldri filnavn).
  static String? extractResourceIdFromBytes(Uint8List bytes) {
    final ranked = extractResourceIdCandidatesFromBytes(bytes);
    if (ranked.isEmpty) return null;
    final best = ranked.first;
    if (best.score < _minAcceptScore) return null;
    return best.code;
  }

  /// Alle kandidater sortert etter sannsynlighet (høyest score først).
  static List<MaviResourceIdCandidate> extractResourceIdCandidatesFromBytes(
    Uint8List bytes,
  ) {
    final merged = <String, MaviResourceIdCandidate>{};
    void absorb(String text, int pageIndex) {
      for (final c in _rankResourceIdCandidates(text, pageIndex: pageIndex)) {
        final prev = merged[c.code];
        if (prev == null || c.score > prev.score) {
          merged[c.code] = c;
        }
      }
    }

    try {
      final doc = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(doc);
      final pageCount = doc.pages.count;
      final scanPages = pageCount.clamp(0, 6);

      for (var p = 0; p < scanPages; p++) {
        final layout = extractor.extractText(
          startPageIndex: p,
          endPageIndex: p,
          layoutText: true,
        );
        final linear = extractor.extractText(
          startPageIndex: p,
          endPageIndex: p,
          layoutText: false,
        );
        absorb('$layout\n$linear', p);
      }

      absorb(extractor.extractText(layoutText: true), 0);
      absorb(extractor.extractText(layoutText: false), 0);
      doc.dispose();
    } catch (_) {
      absorb(extractFullText(bytes), 0);
    }

    final out = merged.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  /// Filnavn brukes ikke — kan være feil. Beholdt for API-kompatibilitet.
  static String? extractResourceIdFromFileName(String fileName) => null;

  static const int _minAcceptScore = 28;

  static List<MaviResourceIdCandidate> _rankResourceIdCandidates(
    String raw, {
    int pageIndex = 0,
  }) {
    if (raw.trim().isEmpty) return const [];
    final text = raw.replaceAll('\uFF3F', '_').replaceAll('\u2013', '-');
    final byCode = <String, MaviResourceIdCandidate>{};

    void consider(RegExpMatch m, {required bool fullNoOm}) {
      final digits = m.group(1);
      if (digits == null || digits.isEmpty) return;
      final code = _codeFromDigits(digits);
      if (code == null || !_isPlausibleMaviNumber(code)) return;

      final start = m.start.clamp(0, text.length);
      final end = m.end.clamp(0, text.length);
      final ctxStart = (start - 100).clamp(0, text.length);
      final ctxEnd = (end + 100).clamp(0, text.length);
      final context = text.substring(ctxStart, ctxEnd);

      var score = fullNoOm ? 52 : 18;
      if (pageIndex == 0) score += 22;
      if (pageIndex == 1) score += 10;
      if (pageIndex >= 4) score -= 12;

      final ctxLower = context.toLowerCase();
      if (RegExp(r'resource\s*(?:id|no|number|#)?', caseSensitive: false).hasMatch(ctxLower)) {
        score += 45;
      }
      if (ctxLower.contains('trip overview') || ctxLower.contains('tripoverview')) {
        score += 38;
      }
      if (RegExp(r'\bvehicle\b', caseSensitive: false).hasMatch(ctxLower)) score += 22;
      if (ctxLower.contains('unit') && ctxLower.contains('code')) score += 24;
      if (ctxLower.contains('mavi')) score += 20;
      if (ctxLower.contains('registration') || ctxLower.contains('registrer')) score += 12;
      if (ctxLower.contains('driver') || ctxLower.contains('sjåfør')) score += 10;

      if (RegExp(r'stop\s*#', caseSensitive: false).hasMatch(ctxLower)) score -= 35;
      if (ctxLower.contains('customer') && !ctxLower.contains('resource')) score -= 18;
      if (ctxLower.contains('+47') || RegExp(r'\b\d{8}\b').hasMatch(ctxLower)) score -= 42;
      if (ctxLower.contains('freight') || ctxLower.contains('delivery')) score -= 8;

      final lineStart = text.lastIndexOf('\n', start - 1) + 1;
      final lineEnd = text.indexOf('\n', end);
      final line = text.substring(
        lineStart,
        lineEnd < 0 ? text.length : lineEnd,
      );
      if (RegExp(r'resource\s*id\s*[:=]?\s*', caseSensitive: false).hasMatch(line)) {
        score += 30;
      }

      final snippet = context.length > 80 ? '…${context.substring(context.length - 77)}' : context;
      final prev = byCode[code];
      if (prev == null || score > prev.score) {
        byCode[code] = MaviResourceIdCandidate(
          code: code,
          score: score,
          pageIndex: pageIndex,
          contextSnippet: snippet.trim(),
          fullFormat: fullNoOm,
        );
      }
    }

    final fullPatterns = <RegExp>[
      RegExp(r'NO\s*[_\s.-]*O\s*[_\s.-]*M\s*0*(\d{1,5})\b', caseSensitive: false),
      RegExp(r'NO_O_(M\d{1,5})\b', caseSensitive: false),
    ];
    for (final re in fullPatterns) {
      for (final m in re.allMatches(text)) {
        consider(m, fullNoOm: true);
      }
    }

    final labeled = RegExp(
      r'(?:resource\s*(?:id|no|number|#)?|vehicle\s*(?:id|no|#)?|unit\s*code)\s*[:=\s#-]*\s*(?:NO\s*[_\s.-]*O\s*[_\s.-]*M\s*0*)?M?\s*0*(\d{1,5})\b',
      caseSensitive: false,
    );
    for (final m in labeled.allMatches(text)) {
      consider(m, fullNoOm: false);
    }

    final bareM = RegExp(r'(?<![A-Z0-9])M\s*0*(\d{1,5})\b', caseSensitive: false);
    for (final m in bareM.allMatches(text)) {
      consider(m, fullNoOm: false);
    }

    final out = byCode.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  static String? _codeFromDigits(String digits) {
    final n = int.tryParse(digits.replaceAll(RegExp(r'\D'), ''));
    if (n == null || n < 1 || n > 99999) return null;
    return 'M$n';
  }

  static bool _isPlausibleMaviNumber(String code) {
    final n = int.tryParse(code.replaceFirst(RegExp(r'^M', caseSensitive: false), ''));
    if (n == null) return false;
    return n >= 1 && n <= 9999;
  }

  /// Flere nøkler per bil (M42, NO_O_M0042, …) for robust matching.
  static Map<String, T> buildVehicleLookupMap<T>({
    required Iterable<T> vehicles,
    required String Function(T) unitCodeOf,
    String? Function(T)? registrationOf,
  }) {
    final map = <String, T>{};
    void put(String? key, T v) {
      if (key == null || key.isEmpty) return;
      final norm = normalizeUnitCodeForMatch(key);
      if (norm.isNotEmpty) map.putIfAbsent(norm, () => v);
      final compact = key.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
      if (compact.isNotEmpty) map.putIfAbsent(compact, () => v);
    }
    for (final v in vehicles) {
      put(unitCodeOf(v), v);
      final reg = registrationOf?.call(v);
      if (reg != null && reg.trim().isNotEmpty) put(reg, v);
    }
    return map;
  }

  static T? findVehicleInLookup<T>(
    Map<String, T> map,
    String? code,
  ) {
    if (code == null || code.isEmpty) return null;
    final norm = normalizeUnitCodeForMatch(code);
    final compact = code.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');
    return map[norm] ?? map[compact];
  }
}

/// Ett funnet MAVI-nummer i PDF med konfidens-score.
class MaviResourceIdCandidate {
  final String code;
  final int score;
  final int pageIndex;
  final String contextSnippet;
  final bool fullFormat;

  const MaviResourceIdCandidate({
    required this.code,
    required this.score,
    required this.pageIndex,
    required this.contextSnippet,
    required this.fullFormat,
  });
}
