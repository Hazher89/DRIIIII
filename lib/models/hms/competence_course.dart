class CompetenceCourse {
  final String id;
  final String companyId;
  final String name;
  final String? description;
  final String category;
  final bool requiresExpiry;
  final int defaultValidityMonths;
  final bool isMandatory;
  final int sortOrder;
  final bool isActive;

  const CompetenceCourse({
    required this.id,
    required this.companyId,
    required this.name,
    this.description,
    this.category = 'generelt',
    this.requiresExpiry = true,
    this.defaultValidityMonths = 60,
    this.isMandatory = false,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory CompetenceCourse.fromJson(Map<String, dynamic> json) {
    return CompetenceCourse(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      category: json['category'] as String? ?? 'generelt',
      requiresExpiry: json['requires_expiry'] as bool? ?? true,
      defaultValidityMonths: json['default_validity_months'] as int? ?? 60,
      isMandatory: json['is_mandatory'] as bool? ?? false,
      sortOrder: json['sort_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'company_id': companyId,
        'name': name,
        'description': description,
        'category': category,
        'requires_expiry': requiresExpiry,
        'default_validity_months': defaultValidityMonths,
        'is_mandatory': isMandatory,
        'sort_order': sortOrder,
        'is_active': isActive,
      };
}
