import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../models/gm_storo_scan.dart';

/// Parser for Elgiganten Logistik / Elkjøp hub shipping labels.
class GmStoroLabelParser {
  static final _ssccRe = RegExp(r'\b(00)?(\d{18,20})\b');
  static final _packageRe = RegExp(r'Package\s*(\d{6,12})', caseSensitive: false);
  static final _shipmentRe = RegExp(r'Shipment\s*(\d{8,12})', caseSensitive: false);
  static final _consigneeRe = RegExp(r'Consignee\s*(\d{3,6})', caseSensitive: false);
  static final _weightRe = RegExp(
    r'Weight\s*([\d]+[,.][\d]+\s*kg)',
    caseSensitive: false,
  );
  static final _readyTimeRe = RegExp(
    r'Ready\s*Time\s*:?\s*(\d{4}-\d{2}-\d{2})?\s*(\d{1,2}:\d{2})',
    caseSensitive: false,
  );
  static final _articleEgRe = RegExp(r'Article\s*EG\s*(\d+)', caseSensitive: false);
  static final _articleNdcRe = RegExp(r'Article\s*NDC\s*(\S+)', caseSensitive: false);
  static final _areaRe = RegExp(r'(U\d+\s+AREA\s*:[^\n]+)', caseSensitive: false);
  static final _toBlockRe = RegExp(
    r'To\s+ELKJ[ØO]P\s+([^\n]+)\n([^\n]+)\n(\d{4}\s+[^\n]+)',
    caseSensitive: false,
  );
  static final _elkjopLineRe = RegExp(
    r'ELKJ[ØO]P\s+(GLASMAGASINET|STORO)',
    caseSensitive: false,
  );
  static final _senderRe = RegExp(
    r'(?:From\s+)?(Elgiganten\s+Logistik\s+AB[^\n]*)',
    caseSensitive: false,
  );
  static final _unitRe = RegExp(r'\b(PALL|Kolli)\b', caseSensitive: false);

  static GmStoroLabelData parseBarcode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const GmStoroLabelData();
    final trimmed = raw.trim();

    // GS1 Application Identifier (00) = SSCC
    final gs1 = RegExp(r'\(00\)\s*(\d{18})').firstMatch(trimmed);
    if (gs1 != null) {
      return GmStoroLabelData(
        sscc: gs1.group(1),
        barcodeRaw: trimmed,
        rawText: trimmed,
      );
    }

    final cleaned = trimmed.replaceAll(RegExp(r'[^\d]'), '');
    String? sscc;
    if (cleaned.length >= 20 && cleaned.startsWith('00')) {
      sscc = cleaned.substring(2, 20);
    } else if (cleaned.length >= 18) {
      sscc = cleaned.length > 18
          ? cleaned.substring(cleaned.length - 18)
          : cleaned;
    }

    return GmStoroLabelData(
      sscc: sscc,
      barcodeRaw: trimmed,
      rawText: trimmed,
    );
  }

  /// Prøver alle strekkoder i et kamerabilde — returnerer første gyldige SSCC.
  static GmStoroLabelData parseFromCapture(BarcodeCapture capture) {
    GmStoroLabelData? fallback;
    for (final bc in capture.barcodes) {
      for (final candidate in <String?>[
        bc.rawValue,
        bc.displayValue,
      ]) {
        if (candidate == null || candidate.trim().isEmpty) continue;
        final parsed = parseBarcode(candidate);
        final key = normalizeSscc(parsed.sscc);
        if (key.length == 18) return parsed;
        if (fallback == null && parsed.sscc != null) fallback = parsed;
      }
    }
    return fallback ?? const GmStoroLabelData();
  }

  static GmStoroLabelData parseOcrText(String text) {
    if (text.trim().isEmpty) return const GmStoroLabelData();
    final normalized = text.replaceAll('\r', '\n');

    String? sscc;
    final ssccLabel = RegExp(r'SSCC\s*:?\s*(\d{18,20})', caseSensitive: false)
        .firstMatch(normalized);
    if (ssccLabel != null) {
      sscc = ssccLabel.group(1);
    } else {
      for (final match in _ssccRe.allMatches(normalized)) {
        final s = match.group(2);
        if (s != null && s.length >= 18) {
          sscc = s;
          break;
        }
      }
    }

    final package = _packageRe.firstMatch(normalized)?.group(1);
    final shipment = _shipmentRe.firstMatch(normalized)?.group(1);
    final consignee = _consigneeRe.firstMatch(normalized)?.group(1);
    final weight = _weightRe.firstMatch(normalized)?.group(1)?.replaceAll(',', '.');
    final ready = _readyTimeRe.firstMatch(normalized);
    final articleEg = _articleEgRe.firstMatch(normalized)?.group(1);
    final articleNdc = _articleNdcRe.firstMatch(normalized)?.group(1);
    final area = _areaRe.firstMatch(normalized)?.group(1)?.trim();
    final unit = _unitRe.firstMatch(normalized)?.group(1);
    final sender = _senderRe.firstMatch(normalized)?.group(1)?.trim();

    String? recipientName;
    String? recipientAddress;
    String? recipientPostal;
    final toMatch = _toBlockRe.firstMatch(normalized);
    if (toMatch != null) {
      recipientName = 'ELKJØP ${toMatch.group(1)?.trim()}';
      recipientAddress = toMatch.group(2)?.trim();
      recipientPostal = toMatch.group(3)?.trim();
    } else {
      final elk = _elkjopLineRe.firstMatch(normalized);
      if (elk != null) {
        recipientName = 'ELKJØP ${elk.group(1)?.toUpperCase()}';
      }
    }

    final destination = _detectDestination(normalized, recipientName);

    // Fallback consignee: stor tall etter To-blokk
    var consigneeFinal = consignee;
    if (consigneeFinal == null) {
      final bigNum = RegExp(r'Consignee[^\d]*(\d{3,5})', caseSensitive: false)
          .firstMatch(normalized);
      consigneeFinal = bigNum?.group(1);
    }

    return GmStoroLabelData(
      sscc: sscc,
      packageId: package,
      shipmentId: shipment,
      consignee: consigneeFinal,
      recipientName: recipientName,
      recipientAddress: recipientAddress,
      recipientPostal: recipientPostal,
      weightKg: weight,
      readyTime: ready?.group(2),
      readyDate: ready?.group(1),
      articleEg: articleEg,
      articleNdc: articleNdc,
      areaCode: area,
      unitType: unit,
      senderName: sender,
      destination: destination,
      rawText: normalized,
    );
  }

  static GmStoroLabelData parseCombined({String? barcode, String? ocrText}) {
    return parseBarcode(barcode).merge(parseOcrText(ocrText ?? ''));
  }

  static String? _detectDestination(String text, String? recipientName) {
    final hay = '${text.toUpperCase()} ${recipientName?.toUpperCase() ?? ''}';
    if (hay.contains('GLASMAGASINET') || hay.contains('STORTORGET')) return 'gm';
    if (hay.contains('ELKJOP STORO') || hay.contains('ELKJØP STORO') ||
        hay.contains('INDUSTRIVEIEN')) {
      return 'storo';
    }
    return 'other';
  }

  static String normalizeSscc(String? value) {
    if (value == null) return '';
    final digits = value.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length >= 18) return digits.substring(digits.length - 18);
    return digits;
  }
}
