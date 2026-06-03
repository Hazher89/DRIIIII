import 'dart:typed_data';

import '../../../models/partner/partner_summary_meta.dart';
import 'mavi_unit_codes.dart';
import 'route_pdf_text_service.dart';

/// Parser for Elkjøp/MAVI sjåfør-oppsummerings-PDF.
class PartnerSummaryParser {
  PartnerSummaryParser._();

  static PartnerSummaryMeta? parse(Uint8List bytes, {String? fileName}) {
    final header = RoutePdfTextService.extractHeaderText(bytes);
    final full = header.length >= 80 ? header : RoutePdfTextService.extractFullText(bytes);
    final text = full.isNotEmpty ? full : header;
    if (text.trim().isEmpty) return null;

    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    var companyName = _companyFromLines(lines) ?? _companyFromFileName(fileName);
    var weekLabel = _weekFromText(text) ?? _weekFromFileName(fileName) ?? '';
    final invoiceDate = _dateFromText(text, 'Fakturadato');
    final paymentDate = _dateFromText(text, 'Betalingsdato');
    final vehicles = _vehiclesFromText(text);

    if (companyName == null && vehicles.isEmpty) return null;
    companyName ??= 'Ukjent bedrift';
    if (weekLabel.isEmpty && fileName != null) {
      weekLabel = _weekFromFileName(fileName) ?? '—';
    }

    return PartnerSummaryMeta(
      weekLabel: weekLabel,
      invoiceDate: invoiceDate,
      paymentDate: paymentDate,
      companyNameRaw: companyName,
      vehicles: vehicles,
      sourceFileName: fileName,
    );
  }

  static String? _companyFromLines(List<String> lines) {
    for (final line in lines.take(8)) {
      if (!line.toLowerCase().contains('oppsummering')) {
        final m = RegExp(r'^[\d,\s]+\s*-\s*(.+)$').firstMatch(line);
        if (m != null) {
          final name = m.group(1)!.trim();
          if (name.isNotEmpty && !name.toLowerCase().startsWith('omsetning')) {
            return name;
          }
        }
      }
    }
    return null;
  }

  static String? _companyFromFileName(String? fileName) {
    if (fileName == null) return null;
    final base = fileName.replaceAll('.pdf', '').trim();
    final m = RegExp(r'-\s*(.+?)\s+\d{1,2}-\d{1,2}$', caseSensitive: false).firstMatch(base);
    if (m != null) return m.group(1)!.trim();
    final m2 = RegExp(r'-\s*(.+)$').firstMatch(base);
    return m2?.group(1)?.trim();
  }

  static String? _weekFromText(String text) {
    final m = RegExp(r'Uke\s+(\d{1,2}\s*-\s*\d{1,2})', caseSensitive: false).firstMatch(text);
    if (m == null) return null;
    return m.group(1)!.replaceAll(' ', '');
  }

  static String? _weekFromFileName(String? fileName) {
    if (fileName == null) return null;
    final m = RegExp(r'(\d{1,2}-\d{1,2})\.pdf$', caseSensitive: false).firstMatch(fileName);
    return m?.group(1);
  }

  static DateTime? _dateFromText(String text, String label) {
    final m = RegExp('$label\\s+(\\d{2}/\\d{2}/\\d{4})', caseSensitive: false).firstMatch(text);
    if (m == null) return null;
    final parts = m.group(1)!.split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  static List<PartnerSummaryVehicleLine> _vehiclesFromText(String text) {
    final re = RegExp(
      r'(\d{1,4})\s*-\s*Transporttjenester eks mva\s+([\d\s.,]+)',
      caseSensitive: false,
    );
    final out = <PartnerSummaryVehicleLine>[];
    final seen = <int>{};
    for (final m in re.allMatches(text)) {
      final num = int.tryParse(m.group(1)!);
      if (num == null || seen.contains(num)) continue;
      seen.add(num);
      final amount = _parseNorwegianAmount(m.group(2)!);
      if (amount == null) continue;
      out.add(
        PartnerSummaryVehicleLine(
          maviNumber: num,
          unitCode: MaviUnitCodes.normalize('NO_O_M$num'),
          transportExVat: amount,
        ),
      );
    }
    out.sort((a, b) => a.maviNumber.compareTo(b.maviNumber));
    return out;
  }

  static double? _parseNorwegianAmount(String raw) {
    var s = raw.trim();
    if (s.isEmpty || s == '-') return null;
    s = s.replaceAll(' ', '').replaceAll('\u00a0', '');
    if (s.contains(',')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    }
    return double.tryParse(s);
  }
}
