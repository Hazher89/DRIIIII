import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

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

    // Lengre query = strammere krav
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
