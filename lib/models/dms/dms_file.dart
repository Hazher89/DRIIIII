class DmsFile {
  final String id;
  final String companyId;
  final String? folderId;
  final String name;
  final String storagePath;
  final int? fileSize;
  final String? extension;
  final String? createdBy;
  final bool isStarred;
  final DateTime createdAt;
  final DateTime updatedAt;

  DmsFile({
    required this.id,
    required this.companyId,
    this.folderId,
    required this.name,
    required this.storagePath,
    this.fileSize,
    this.extension,
    this.createdBy,
    this.isStarred = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DmsFile.fromJson(Map<String, dynamic> json) {
    return DmsFile(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      folderId: json['folder_id'] as String?,
      name: json['name'] as String,
      storagePath: json['storage_path'] as String,
      fileSize: json['file_size'] as int?,
      extension: json['extension'] as String?,
      createdBy: json['created_by'] as String?,
      isStarred: json['is_starred'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'company_id': companyId,
    'folder_id': folderId,
    'name': name,
    'storage_path': storagePath,
    'file_size': fileSize,
    'extension': extension,
    'created_by': createdBy,
  };
}
