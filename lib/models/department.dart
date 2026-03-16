class Department {
  final String id;
  final String companyId;
  final String name;
  final String? description;
  final String? leaderId;
  final String colorCode;
  final String iconName;
  final String? parentDepartmentId;
  final DateTime? createdAt;

  const Department({
    required this.id,
    required this.companyId,
    required this.name,
    this.description,
    this.leaderId,
    this.colorCode = '#2E7D32',
    this.iconName = 'business',
    this.parentDepartmentId,
    this.createdAt,
  });

  factory Department.fromJson(Map<String, dynamic> json) {
    return Department(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      leaderId: json['leader_id'] as String?,
      colorCode: json['color_code'] as String? ?? '#2E7D32',
      iconName: json['icon_name'] as String? ?? 'business',
      parentDepartmentId: json['parent_department_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'company_id': companyId,
    'name': name,
    'description': description,
    'leader_id': leaderId,
    'color_code': colorCode,
    'icon_name': iconName,
    'parent_department_id': parentDepartmentId,
  };
}
