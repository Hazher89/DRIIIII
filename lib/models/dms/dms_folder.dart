import 'package:uuid/uuid.dart';

class DmsFolder {
  final String id;
  final String companyId;
  final String name;
  final String? parentId;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  DmsFolder({
    required this.id,
    required this.companyId,
    required this.name,
    this.parentId,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DmsFolder.fromJson(Map<String, dynamic> json) {
    return DmsFolder(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      name: json['name'] as String,
      parentId: json['parent_id'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'company_id': companyId,
    'name': name,
    'parent_id': parentId,
    'created_by': createdBy,
  };
}
