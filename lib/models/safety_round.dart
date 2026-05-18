class SafetyRound {
  final String id;
  final String companyId;
  final String? departmentId;
  final String conductedBy;
  final String title;
  final String? templateId;
  final String? location;
  final String? archiveNumber;
  final List<Map<String, dynamic>> checklist;
  final List<Map<String, dynamic>> findings;
  final String overallStatus;
  final DateTime? scheduledDate;
  final DateTime? completedAt;
  final DateTime? nextRoundDate;
  final List<String> imageUrls;
  final String? pdfUrl;
  final Map<String, dynamic> signature;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final String? conductorName;

  const SafetyRound({
    required this.id,
    required this.companyId,
    this.departmentId,
    required this.conductedBy,
    required this.title,
    this.templateId,
    this.location,
    this.archiveNumber,
    this.checklist = const [],
    this.findings = const [],
    this.overallStatus = 'planlagt',
    this.scheduledDate,
    this.completedAt,
    this.nextRoundDate,
    this.imageUrls = const [],
    this.pdfUrl,
    this.signature = const {},
    this.createdAt,
    this.updatedAt,
    this.conductorName,
  });

  DateTime? get signedAt {
    final s = signature['signed_at'];
    if (s == null) return null;
    return DateTime.tryParse(s as String);
  }

  String? get signedByName => signature['signed_by_name'] as String?;
  String? get signerRole => signature['signer_role'] as String?;

  List<String> get participantIds =>
      (signature['participant_ids'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ??
      [];

  List<String> get participantNames =>
      (signature['participant_names'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ??
      [];

  String? get roundNotes => signature['notes'] as String?;

  SafetyRound copyWith({
    String? pdfUrl,
    Map<String, dynamic>? signature,
    String? overallStatus,
    DateTime? completedAt,
    String? archiveNumber,
    DateTime? nextRoundDate,
  }) {
    return SafetyRound(
      id: id,
      companyId: companyId,
      departmentId: departmentId,
      conductedBy: conductedBy,
      title: title,
      templateId: templateId,
      location: location,
      archiveNumber: archiveNumber ?? this.archiveNumber,
      checklist: checklist,
      findings: findings,
      overallStatus: overallStatus ?? this.overallStatus,
      scheduledDate: scheduledDate,
      completedAt: completedAt ?? this.completedAt,
      nextRoundDate: nextRoundDate ?? this.nextRoundDate,
      imageUrls: imageUrls,
      pdfUrl: pdfUrl ?? this.pdfUrl,
      signature: signature ?? this.signature,
      createdAt: createdAt,
      updatedAt: updatedAt,
      conductorName: conductorName,
    );
  }

  int get okCount =>
      checklist.where((e) => e['status'] == 'ok').length;
  int get avvikCount =>
      checklist.where((e) => e['status'] == 'avvik').length;

  factory SafetyRound.fromJson(Map<String, dynamic> json) {
    return SafetyRound(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      departmentId: json['department_id'] as String?,
      conductedBy: json['conducted_by'] as String,
      title: json['title'] as String,
      templateId: json['template_id'] as String?,
      location: json['location'] as String?,
      archiveNumber: json['archive_number'] as String?,
      checklist: (json['checklist'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
      findings: (json['findings'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
      overallStatus: json['overall_status'] as String? ?? 'planlagt',
      scheduledDate: json['scheduled_date'] != null
          ? DateTime.parse(json['scheduled_date'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      nextRoundDate: json['next_round_date'] != null
          ? DateTime.parse(json['next_round_date'] as String)
          : null,
      imageUrls: (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      pdfUrl: json['pdf_url'] as String?,
      signature: json['signature'] is Map<String, dynamic>
          ? json['signature'] as Map<String, dynamic>
          : {},
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      conductorName: _conductorFromJson(json),
    );
  }

  static String? _conductorFromJson(Map<String, dynamic> json) {
    final profiles = json['profiles'];
    if (profiles is Map && profiles['full_name'] != null) {
      return profiles['full_name'] as String;
    }
    final sig = json['signature'];
    if (sig is Map && sig['signed_by_name'] != null) {
      return sig['signed_by_name'] as String;
    }
    return null;
  }

  Map<String, dynamic> toInsertJson() => {
        'company_id': companyId,
        'department_id': departmentId,
        'conducted_by': conductedBy,
        'title': title,
        'template_id': templateId,
        'location': location,
        'archive_number': archiveNumber,
        'checklist': checklist,
        'findings': findings,
        'overall_status': overallStatus,
        'scheduled_date': scheduledDate?.toIso8601String().split('T').first,
        'completed_at': completedAt?.toIso8601String(),
        'next_round_date': nextRoundDate?.toIso8601String().split('T').first,
        'image_urls': imageUrls,
        'pdf_url': pdfUrl,
        'signature': signature,
      };
}
