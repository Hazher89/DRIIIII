class SharedPartnerDocument {
  final String id;
  final String companyId;
  final String title;
  final String storagePath;
  final String? fileName;
  final String? mimeType;
  final String category;
  final bool isActive;
  final DateTime createdAt;

  const SharedPartnerDocument({
    required this.id,
    required this.companyId,
    required this.title,
    required this.storagePath,
    this.fileName,
    this.mimeType,
    this.category = 'routine',
    this.isActive = true,
    required this.createdAt,
  });

  factory SharedPartnerDocument.fromJson(Map<String, dynamic> json) {
    return SharedPartnerDocument(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      title: json['title'] as String? ?? 'Dokument',
      storagePath: json['storage_path'] as String? ?? '',
      fileName: json['file_name'] as String?,
      mimeType: json['mime_type'] as String?,
      category: json['category'] as String? ?? 'routine',
      isActive: json['is_active'] == true,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertJson({String? createdBy}) => {
        'company_id': companyId,
        'title': title,
        'storage_path': storagePath,
        'file_name': fileName,
        'mime_type': mimeType,
        'category': category,
        'is_active': isActive,
        if (createdBy != null) 'created_by': createdBy,
      };
}
