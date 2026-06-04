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
  final String? contentSha256;
  final String? importedRouteShareId;
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
    this.contentSha256,
    this.importedRouteShareId,
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
      contentSha256: json['content_sha256'] as String?,
      importedRouteShareId: json['imported_route_share_id'] as String?,
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

/// PDF som ikke kunne auto-fordes — vises i «Hoppet over» (samme som AUTO MASS).
class SapRouteImportSkippedItem {
  final String inboxId;
  final String fileName;
  final List<int> bytes;
  final String reason;
  final String? detectedCode;

  const SapRouteImportSkippedItem({
    required this.inboxId,
    required this.fileName,
    required this.bytes,
    required this.reason,
    this.detectedCode,
  });
}

class SapRouteImportResult {
  final int imported;
  final int skipped;
  final List<SapRouteImportLine> lines;
  final List<SapRouteImportSkippedItem> skippedItems;

  const SapRouteImportResult({
    required this.imported,
    required this.skipped,
    required this.lines,
    this.skippedItems = const [],
  });
}
