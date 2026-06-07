class DmsFolder {
  final String id;
  final String companyId;
  final String name;
  final String? parentId;
  final String? createdBy;
  final String? description;
  final String? passwordHash;
  final bool isPrivate;
  final bool isSharedMavi;
  final DateTime createdAt;
  final DateTime updatedAt;

  DmsFolder({
    required this.id,
    required this.companyId,
    required this.name,
    this.parentId,
    this.createdBy,
    this.description,
    this.passwordHash,
    this.isPrivate = false,
    this.isSharedMavi = false,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPasswordProtected =>
      passwordHash != null && passwordHash!.isNotEmpty;

  factory DmsFolder.fromJson(Map<String, dynamic> json) {
    return DmsFolder(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      name: json['name'] as String,
      parentId: json['parent_id'] as String?,
      createdBy: json['created_by'] as String?,
      description: json['description'] as String?,
      passwordHash: json['password_hash'] as String?,
      isPrivate: json['is_private'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson({
    String? passwordHash,
    bool? isPrivate,
    bool? isSharedMavi,
    String? description,
  }) =>
      {
        'company_id': companyId,
        'name': name,
        'parent_id': parentId,
        if (description != null) 'description': description,
        if (passwordHash != null && passwordHash.isNotEmpty)
          'password_hash': passwordHash,
        if (isPrivate != null) 'is_private': isPrivate,
        if (isSharedMavi != null) 'is_shared_mavi': isSharedMavi,
      };
}
