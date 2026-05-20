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
}
