import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

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
