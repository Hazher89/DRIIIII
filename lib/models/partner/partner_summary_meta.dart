import 'dart:convert';

/// Metadata for sjåfør-/bedrifts-oppsummering (lagres i partner_documents.description som JSON).
class PartnerSummaryVehicleLine {
  const PartnerSummaryVehicleLine({
    required this.maviNumber,
    required this.unitCode,
    required this.transportExVat,
  });

  final int maviNumber;
  final String unitCode;
  final double transportExVat;

  factory PartnerSummaryVehicleLine.fromJson(Map<String, dynamic> json) {
    return PartnerSummaryVehicleLine(
      maviNumber: json['mavi_number'] as int? ?? 0,
      unitCode: json['unit_code'] as String? ?? '',
      transportExVat: (json['transport_ex_vat'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'mavi_number': maviNumber,
        'unit_code': unitCode,
        'transport_ex_vat': transportExVat,
      };

  String get compactLabel => 'M$maviNumber';
}

class PartnerSummaryMeta {
  const PartnerSummaryMeta({
    required this.weekLabel,
    this.invoiceDate,
    this.paymentDate,
    required this.companyNameRaw,
    required this.vehicles,
    this.sourceFileName,
  });

  final String weekLabel;
  final DateTime? invoiceDate;
  final DateTime? paymentDate;
  final String companyNameRaw;
  final List<PartnerSummaryVehicleLine> vehicles;
  final String? sourceFileName;

  double get transportTotalExVat =>
      vehicles.fold<double>(0, (sum, v) => sum + v.transportExVat);

  bool get hasMultipleVehicles => vehicles.length > 1;

  String toJsonString() => jsonEncode({
        'kind': 'partner_driver_summary',
        'week_label': weekLabel,
        'invoice_date': invoiceDate?.toIso8601String().split('T').first,
        'payment_date': paymentDate?.toIso8601String().split('T').first,
        'company_name_raw': companyNameRaw,
        'source_file_name': sourceFileName,
        'vehicles': vehicles.map((v) => v.toJson()).toList(),
      });

  static PartnerSummaryMeta? tryParseFromDescription(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['kind'] != 'partner_driver_summary') return null;
      DateTime? parseDate(String? v) {
        if (v == null || v.isEmpty) return null;
        return DateTime.tryParse(v);
      }

      final vehicleList = (map['vehicles'] as List<dynamic>? ?? [])
          .map((e) => PartnerSummaryVehicleLine.fromJson(e as Map<String, dynamic>))
          .toList();

      return PartnerSummaryMeta(
        weekLabel: map['week_label'] as String? ?? '',
        invoiceDate: parseDate(map['invoice_date'] as String?),
        paymentDate: parseDate(map['payment_date'] as String?),
        companyNameRaw: map['company_name_raw'] as String? ?? '',
        vehicles: vehicleList,
        sourceFileName: map['source_file_name'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  static String formatAmount(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final dec = parts.length > 1 ? parts[1] : '00';
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(' ');
      buf.write(intPart[i]);
    }
    return '${buf.toString()},$dec';
  }

  static String formatDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }
}
