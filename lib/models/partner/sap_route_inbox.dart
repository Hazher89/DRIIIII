class SapRouteInboxItem {
  final String id;
  final String companyId;
  final String status;
  final String? senderEmail;
  final String? senderName;
  final String? subject;
  final String fileName;
  final String pdfStoragePath;
  final String? resendEmailId;
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
    this.resendEmailId,
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
      resendEmailId: json['resend_email_id'] as String?,
      detectedMaviCode: json['detected_mavi_code'] as String?,
      rejectReason: json['reject_reason'] as String?,
      contentSha256: json['content_sha256'] as String?,
      importedRouteShareId: json['imported_route_share_id'] as String?,
      receivedAt: DateTime.parse(json['received_at'] as String),
    );
  }
}

/// Tydelig status før utsending av SAP-ruter.
class SapInboxOverview {
  const SapInboxOverview({
    required this.pendingMails,
    required this.pendingPdfs,
    required this.stagedInQueue,
    required this.readyToPublish,
    required this.missingShift,
    required this.manualPending,
    this.latestReceivedAt,
    this.duplicateExtras = 0,
    this.identicalAlreadySent = 0,
  });

  final int pendingMails;
  final int pendingPdfs;
  final int stagedInQueue;
  final int readyToPublish;
  final int missingShift;
  final int manualPending;
  final DateTime? latestReceivedAt;
  final int duplicateExtras;
  final int identicalAlreadySent;

  /// Hvor lenge vi venter etter siste PDF før vi antar at batchen er ferdig.
  static const settleQuiet = Duration(seconds: 90);

  static const empty = SapInboxOverview(
    pendingMails: 0,
    pendingPdfs: 0,
    stagedInQueue: 0,
    readyToPublish: 0,
    missingShift: 0,
    manualPending: 0,
  );

  bool get hasAnythingWaiting =>
      pendingPdfs > 0 || stagedInQueue > 0 || manualPending > 0;

  /// Flere PDF kan fortsatt komme inn (eller venter i innboks).
  bool get expectingMoreRoutes =>
      pendingPdfs > 0 ||
      (latestReceivedAt != null &&
          DateTime.now().difference(latestReceivedAt!) < settleQuiet);

  /// Alle mottatte er i kø med skift — trygt å se over og sende.
  bool get isReadyForDispatch =>
      pendingPdfs == 0 &&
      manualPending == 0 &&
      missingShift == 0 &&
      duplicateExtras == 0 &&
      identicalAlreadySent == 0 &&
      stagedInQueue > 0 &&
      readyToPublish > 0 &&
      !expectingMoreRoutes;

  String get readinessLabel {
    if (pendingPdfs > 0) {
      return 'Mottar fortsatt ruter — $pendingPdfs PDF venter på import';
    }
    if (expectingMoreRoutes) {
      return 'Venter litt til — flere ruter kan komme snart';
    }
    if (manualPending > 0) {
      return '$manualPending rute(r) trenger manuell tildeling';
    }
    if (missingShift > 0) {
      return '$missingShift rute(r) mangler skift — fiks før utsending';
    }
    if (duplicateExtras > 0) {
      return '$duplicateExtras duplikat i køen — behold én av hver';
    }
    if (identicalAlreadySent > 0) {
      return '$identicalAlreadySent rute(r) er 100 % like noe sjåføren allerede har fått';
    }
    if (isReadyForDispatch) {
      return 'Klar for utsending — $readyToPublish rute(r) klare';
    }
    if (stagedInQueue == 0) return 'Ingen ruter i kø ennå';
    return '$stagedInQueue i kø — se over før utsending';
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
