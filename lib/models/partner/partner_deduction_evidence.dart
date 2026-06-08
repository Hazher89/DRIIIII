class PartnerDeductionEvidence {
  const PartnerDeductionEvidence({
    required this.id,
    required this.caseId,
    required this.companyId,
    required this.partnerId,
    required this.storageRef,
    required this.storageProvider,
    required this.fileName,
    this.mimeType,
    required this.mediaType,
    this.fileSizeBytes,
    this.dropboxPath,
    required this.ownerVisible,
    this.uploadedBy,
    required this.createdAt,
  });

  final String id;
  final String caseId;
  final String companyId;
  final String partnerId;
  final String storageRef;
  final String storageProvider;
  final String fileName;
  final String? mimeType;
  final String mediaType;
  final int? fileSizeBytes;
  final String? dropboxPath;
  final bool ownerVisible;
  final String? uploadedBy;
  final DateTime createdAt;

  bool get isVideo => mediaType == 'video';
  bool get isImage => mediaType == 'image';

  factory PartnerDeductionEvidence.fromJson(Map<String, dynamic> json) {
    return PartnerDeductionEvidence(
      id: json['id'] as String,
      caseId: json['case_id'] as String,
      companyId: json['company_id'] as String,
      partnerId: json['partner_id'] as String,
      storageRef: json['storage_ref'] as String,
      storageProvider: json['storage_provider'] as String? ?? 'dropbox',
      fileName: json['file_name'] as String,
      mimeType: json['mime_type'] as String?,
      mediaType: json['media_type'] as String? ?? 'image',
      fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt(),
      dropboxPath: json['dropbox_path'] as String?,
      ownerVisible: json['owner_visible'] as bool? ?? true,
      uploadedBy: json['uploaded_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
