class Department {
  final String id;
  final String companyId;
  final String name;
  final String? description;
  final String? leaderId;
  /// Alle ledere for avdelingen (kan være flere).
  final List<String> leaderIds;
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
    this.leaderIds = const [],
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
      leaderIds: _parseLeaderIds(json),
      colorCode: json['color_code'] as String? ?? '#2E7D32',
      iconName: json['icon_name'] as String? ?? 'business',
      parentDepartmentId: json['parent_department_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  static List<String> _parseLeaderIds(Map<String, dynamic> json) {
    final raw = json['leader_ids'];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    final single = json['leader_id'] as String?;
    if (single != null && single.isNotEmpty) return [single];
    return const [];
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
