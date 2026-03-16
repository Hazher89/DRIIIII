class SafetyRound {
  final String id;
  final String companyId;
  final String? departmentId;
  final String conductedBy;
  final String title;
  final List<Map<String, dynamic>> checklist;
  final List<Map<String, dynamic>> findings;
  final String overallStatus;
  final DateTime? scheduledDate;
  final DateTime? completedAt;
  final DateTime? nextRoundDate;
  final List<String> imageUrls;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Joined
  final String? conductorName;

  const SafetyRound({
    required this.id,
    required this.companyId,
    this.departmentId,
    required this.conductedBy,
    required this.title,
    this.checklist = const [],
    this.findings = const [],
    this.overallStatus = 'planlagt',
    this.scheduledDate,
    this.completedAt,
    this.nextRoundDate,
    this.imageUrls = const [],
    this.createdAt,
    this.updatedAt,
    this.conductorName,
  });

  factory SafetyRound.fromJson(Map<String, dynamic> json) {
    return SafetyRound(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      departmentId: json['department_id'] as String?,
      conductedBy: json['conducted_by'] as String,
      title: json['title'] as String,
      checklist: (json['checklist'] as List<dynamic>?)?.map((e) => e as Map<String, dynamic>).toList() ?? [],
      findings: (json['findings'] as List<dynamic>?)?.map((e) => e as Map<String, dynamic>).toList() ?? [],
      overallStatus: json['overall_status'] as String? ?? 'planlagt',
      scheduledDate: json['scheduled_date'] != null ? DateTime.parse(json['scheduled_date'] as String) : null,
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at'] as String) : null,
      nextRoundDate: json['next_round_date'] != null ? DateTime.parse(json['next_round_date'] as String) : null,
      imageUrls: (json['image_urls'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null,
      conductorName: json['profiles'] != null ? json['profiles']['full_name'] as String? : null,
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'company_id': companyId,
    'department_id': departmentId,
    'conducted_by': conductedBy,
    'title': title,
    'checklist': checklist,
    'findings': findings,
    'overall_status': overallStatus,
    'scheduled_date': scheduledDate?.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
    'next_round_date': nextRoundDate?.toIso8601String(),
    'image_urls': imageUrls,
  };
}
