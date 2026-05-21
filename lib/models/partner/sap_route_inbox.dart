class SapRouteInboxItem {
  final String id;
  final String companyId;
  final String status;
  final String? senderEmail;
  final String? senderName;
  final String? subject;
  final String fileName;
  final String pdfStoragePath;
  final String? detectedMaviCode;
  final String? rejectReason;
  final DateTime receivedAt;

  const SapRouteInboxItem({
    required this.id,
    required this.companyId,
    required this.status,
    this.senderEmail,
    this.senderName,
    this.subject,
    required this.fileName,
    required this.pdfStoragePath,
    this.detectedMaviCode,
    this.rejectReason,
    required this.receivedAt,
  });

  factory SapRouteInboxItem.fromJson(Map<String, dynamic> json) {
    return SapRouteInboxItem(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      status: json['status'] as String? ?? 'pending',
      senderEmail: json['sender_email'] as String?,
      senderName: json['sender_name'] as String?,
      subject: json['subject'] as String?,
      fileName: json['file_name'] as String,
      pdfStoragePath: json['pdf_storage_path'] as String,
      detectedMaviCode: json['detected_mavi_code'] as String?,
      rejectReason: json['reject_reason'] as String?,
      receivedAt: DateTime.parse(json['received_at'] as String),
    );
  }
}

class SapRouteImportLine {
  final String fileName;
  final bool ok;
  final String? maviCode;
  final String? message;

  const SapRouteImportLine({
    required this.fileName,
    required this.ok,
    this.maviCode,
    this.message,
  });
}

class SapRouteImportResult {
  final int imported;
  final int skipped;
  final List<SapRouteImportLine> lines;

  const SapRouteImportResult({
    required this.imported,
    required this.skipped,
    required this.lines,
  });
}
