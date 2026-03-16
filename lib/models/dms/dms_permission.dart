enum DmsPermissionType { view, edit, admin }

class DmsPermission {
  final String id;
  final String? folderId;
  final String? fileId;
  final String userId;
  final DmsPermissionType type;

  DmsPermission({
    required this.id,
    this.folderId,
    this.fileId,
    required this.userId,
    required this.type,
  });

  factory DmsPermission.fromJson(Map<String, dynamic> json) {
    return DmsPermission(
      id: json['id'] as String,
      folderId: json['folder_id'] as String?,
      fileId: json['file_id'] as String?,
      userId: json['user_id'] as String,
      type: DmsPermissionType.values.firstWhere(
        (e) => e.name == json['permission_type'],
        orElse: () => DmsPermissionType.read,
      ),
    );
  }
}
