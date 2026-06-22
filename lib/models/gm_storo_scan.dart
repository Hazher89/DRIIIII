/// Parsed data from Elgiganten/Elkjøp shipping label.
class GmStoroLabelData {
  const GmStoroLabelData({
    this.sscc,
    this.barcodeRaw,
    this.packageId,
    this.shipmentId,
    this.consignee,
    this.recipientName,
    this.recipientAddress,
    this.recipientPostal,
    this.weightKg,
    this.readyTime,
    this.readyDate,
    this.articleEg,
    this.articleNdc,
    this.areaCode,
    this.unitType,
    this.senderName,
    this.destination,
    this.rawText,
  });

  final String? sscc;
  final String? barcodeRaw;
  final String? packageId;
  final String? shipmentId;
  final String? consignee;
  final String? recipientName;
  final String? recipientAddress;
  final String? recipientPostal;
  final String? weightKg;
  final String? readyTime;
  final String? readyDate;
  final String? articleEg;
  final String? articleNdc;
  final String? areaCode;
  final String? unitType;
  final String? senderName;
  final String? destination;
  final String? rawText;

  /// Kolli (SSCC) er obligatorisk — øvrige felt er valgfrie.
  bool get hasMinimumData =>
      sscc != null && GmStoroLabelData._ssccDigits(sscc!).length >= 18;

  static String _ssccDigits(String value) =>
      value.replaceAll(RegExp(r'[^\d]'), '');

  String get destinationLabel => switch (destination) {
        'gm' => 'Glasmagasinet',
        'storo' => 'Storo',
        _ => 'Annet',
      };

  GmStoroLabelData merge(GmStoroLabelData other) {
    String? pick(String? a, String? b) =>
        (a != null && a.isNotEmpty) ? a : b;

    return GmStoroLabelData(
      sscc: pick(sscc, other.sscc),
      barcodeRaw: pick(barcodeRaw, other.barcodeRaw),
      packageId: pick(packageId, other.packageId),
      shipmentId: pick(shipmentId, other.shipmentId),
      consignee: pick(consignee, other.consignee),
      recipientName: pick(recipientName, other.recipientName),
      recipientAddress: pick(recipientAddress, other.recipientAddress),
      recipientPostal: pick(recipientPostal, other.recipientPostal),
      weightKg: pick(weightKg, other.weightKg),
      readyTime: pick(readyTime, other.readyTime),
      readyDate: pick(readyDate, other.readyDate),
      articleEg: pick(articleEg, other.articleEg),
      articleNdc: pick(articleNdc, other.articleNdc),
      areaCode: pick(areaCode, other.areaCode),
      unitType: pick(unitType, other.unitType),
      senderName: pick(senderName, other.senderName),
      destination: pick(destination, other.destination),
      rawText: pick(rawText, other.rawText),
    );
  }

  Map<String, dynamic> toInsertJson({
    required String companyId,
    required String batchId,
    required String scannedBy,
    bool isDuplicate = false,
  }) {
    return {
      'company_id': companyId,
      'batch_id': batchId,
      'scanned_by': scannedBy,
      'sscc': sscc ?? barcodeRaw ?? packageId ?? 'unknown',
      'barcode_raw': barcodeRaw,
      'package_id': packageId,
      'shipment_id': shipmentId,
      'consignee': consignee,
      'recipient_name': recipientName,
      'recipient_address': recipientAddress,
      'recipient_postal': recipientPostal,
      'weight_kg': weightKg,
      'ready_time': readyTime,
      'ready_date': readyDate,
      'article_eg': articleEg,
      'article_ndc': articleNdc,
      'area_code': areaCode,
      'unit_type': unitType,
      'sender_name': senderName,
      'destination': destination,
      'raw_ocr_text': rawText,
      'is_duplicate': isDuplicate,
    };
  }

  factory GmStoroLabelData.fromRow(Map<String, dynamic> row) {
    return GmStoroLabelData(
      sscc: row['sscc']?.toString(),
      barcodeRaw: row['barcode_raw']?.toString(),
      packageId: row['package_id']?.toString(),
      shipmentId: row['shipment_id']?.toString(),
      consignee: row['consignee']?.toString(),
      recipientName: row['recipient_name']?.toString(),
      recipientAddress: row['recipient_address']?.toString(),
      recipientPostal: row['recipient_postal']?.toString(),
      weightKg: row['weight_kg']?.toString(),
      readyTime: row['ready_time']?.toString(),
      readyDate: row['ready_date']?.toString(),
      articleEg: row['article_eg']?.toString(),
      articleNdc: row['article_ndc']?.toString(),
      areaCode: row['area_code']?.toString(),
      unitType: row['unit_type']?.toString(),
      senderName: row['sender_name']?.toString(),
      destination: row['destination']?.toString(),
      rawText: row['raw_ocr_text']?.toString(),
    );
  }
}

class GmStoroBatch {
  const GmStoroBatch({
    required this.id,
    required this.companyId,
    required this.createdBy,
    required this.status,
    required this.labelCount,
    this.submittedAt,
    required this.createdAt,
    this.scans = const [],
    this.scannerName,
  });

  final String id;
  final String companyId;
  final String createdBy;
  final String status;
  final int labelCount;
  final DateTime? submittedAt;
  final DateTime createdAt;
  final List<GmStoroScanRecord> scans;
  final String? scannerName;

  bool get isDraft => status == 'draft';
  bool get isSubmitted => status == 'submitted';

  factory GmStoroBatch.fromRow(Map<String, dynamic> row, {List<GmStoroScanRecord>? scans}) {
    return GmStoroBatch(
      id: row['id'] as String,
      companyId: row['company_id'] as String,
      createdBy: row['created_by'] as String,
      status: row['status'] as String? ?? 'draft',
      labelCount: (row['label_count'] as num?)?.toInt() ?? 0,
      submittedAt: row['submitted_at'] != null
          ? DateTime.parse(row['submitted_at'] as String)
          : null,
      createdAt: DateTime.parse(row['created_at'] as String),
      scans: scans ?? const [],
      scannerName: row['scanner_name']?.toString(),
    );
  }
}

class GmStoroScanRecord {
  const GmStoroScanRecord({
    required this.id,
    required this.batchId,
    required this.data,
    required this.scannedAt,
    this.isDuplicate = false,
    this.scannerName,
  });

  final String id;
  final String batchId;
  final GmStoroLabelData data;
  final DateTime scannedAt;
  final bool isDuplicate;
  final String? scannerName;

  factory GmStoroScanRecord.fromRow(Map<String, dynamic> row) {
    return GmStoroScanRecord(
      id: row['id'] as String,
      batchId: row['batch_id'] as String,
      data: GmStoroLabelData.fromRow(row),
      scannedAt: DateTime.parse(row['scanned_at'] as String),
      isDuplicate: row['is_duplicate'] == true,
      scannerName: row['scanner_name']?.toString(),
    );
  }
}
