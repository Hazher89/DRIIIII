class RiskAssessment {
  final String id;
  final String companyId;
  final String? departmentId;
  final String createdBy;
  final String title;
  final String? description;
  final String? area;
  final int probability;
  final int consequence;
  final int? riskScore;
  final String? existingMeasures;
  final String? proposedMeasures;
  final String? responsiblePerson;
  final List<String> imageUrls;
  final String status;
  final DateTime? reviewDate;
  final DateTime? createdAt;

  // Joined
  final String? creatorName;

  const RiskAssessment({
    required this.id,
    required this.companyId,
    this.departmentId,
    required this.createdBy,
    required this.title,
    this.description,
    this.area,
    required this.probability,
    required this.consequence,
    this.riskScore,
    this.existingMeasures,
    this.proposedMeasures,
    this.responsiblePerson,
    this.imageUrls = const [],
    this.status = 'aktiv',
    this.reviewDate,
    this.createdAt,
    this.creatorName,
  });

  factory RiskAssessment.fromJson(Map<String, dynamic> json) {
    return RiskAssessment(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      departmentId: json['department_id'] as String?,
      createdBy: json['created_by'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      area: json['area'] as String?,
      probability: json['probability'] as int,
      consequence: json['consequence'] as int,
      riskScore: json['risk_score'] as int?,
      existingMeasures: json['existing_measures'] as String?,
      proposedMeasures: json['proposed_measures'] as String?,
      responsiblePerson: json['responsible_person'] as String?,
      imageUrls: (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      status: json['status'] as String? ?? 'aktiv',
      reviewDate: json['review_date'] != null
          ? DateTime.parse(json['review_date'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      creatorName: json['profiles'] != null
          ? json['profiles']['full_name'] as String?
          : null,
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'company_id': companyId,
    'department_id': departmentId,
    'created_by': createdBy,
    'title': title,
    'description': description,
    'area': area,
    'probability': probability,
    'consequence': consequence,
    'existing_measures': existingMeasures,
    'proposed_measures': proposedMeasures,
    'responsible_person': responsiblePerson,
    'image_urls': imageUrls,
  };

  int get calculatedRiskScore => riskScore ?? (probability * consequence);

  String get riskLevel {
    final score = calculatedRiskScore;
    if (score <= 4) return 'Lav';
    if (score <= 9) return 'Middels';
    if (score <= 14) return 'Høy';
    if (score <= 19) return 'Kritisk';
    return 'Ekstrem';
  }

  bool get isHighRisk => calculatedRiskScore >= 15;
}
