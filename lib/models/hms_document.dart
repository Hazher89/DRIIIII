enum HmsDocumentType { kursbevis, sertifikat, arbeidsavtale, hms_dokument, annet }

extension HmsDocumentTypeExtension on HmsDocumentType {
  String get label {
    switch (this) {
      case HmsDocumentType.kursbevis: return 'Kursbevis';
      case HmsDocumentType.sertifikat: return 'Sertifikat';
      case HmsDocumentType.arbeidsavtale: return 'Arbeidsavtale';
      case HmsDocumentType.hms_dokument: return 'HMS-dokument';
      case HmsDocumentType.annet: return 'Annet';
    }
  }
}

class HmsDocument {
  final String id;
  final String userId;
  final String companyId;
  final HmsDocumentType documentType;
  final String title;
  final String? description;
  final String fileUrl;
  final String? fileName;
  final int? fileSize;
  final DateTime? expiresAt;
  final bool isVerified;
  final String? verifiedBy;
  final String uploadedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const HmsDocument({
    required this.id,
    required this.userId,
    required this.companyId,
    required this.documentType,
    required this.title,
    this.description,
    required this.fileUrl,
    this.fileName,
    this.fileSize,
    this.expiresAt,
    this.isVerified = false,
    this.verifiedBy,
    required this.uploadedBy,
    this.createdAt,
    this.updatedAt,
  });

  factory HmsDocument.fromJson(Map<String, dynamic> json) {
    return HmsDocument(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      companyId: json['company_id'] as String,
      documentType: HmsDocumentType.values.firstWhere(
        (e) => e.name == json['document_type'],
        orElse: () => HmsDocumentType.annet,
      ),
      title: json['title'] as String,
      description: json['description'] as String?,
      fileUrl: json['file_url'] as String,
      fileName: json['file_name'] as String?,
      fileSize: json['file_size'] as int?,
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at'] as String) : null,
      isVerified: json['is_verified'] as bool? ?? false,
      verifiedBy: json['verified_by'] as String?,
      uploadedBy: json['uploaded_by'] as String,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null,
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'user_id': userId,
    'company_id': companyId,
    'document_type': documentType.name,
    'title': title,
    'description': description,
    'file_url': fileUrl,
    'file_name': fileName,
    'file_size': fileSize,
    'expires_at': expiresAt?.toIso8601String(),
    'uploaded_by': uploadedBy,
  };
}
