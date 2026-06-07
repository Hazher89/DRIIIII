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
  final int initialProbability;
  final int initialConsequence;
  final int residualProbability;
  final int residualConsequence;
  final String? existingMeasures;
  final String? proposedMeasures;
  final String? responsiblePerson;
  final List<String> imageUrls;
  final String status;
  final DateTime? reviewDate;
  final DateTime? createdAt;
  final String? templateKey;
  final String? scenarioCategory;
  final bool avvikBoosted;
  final int avvikSignalCount;
  final DateTime? avvikLastSignalAt;
  final String? linkedTicketCategory;

  // Joined
  final String? creatorName;
  final String? responsiblePersonName;

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
    this.initialProbability = 3,
    this.initialConsequence = 3,
    this.residualProbability = 3,
    this.residualConsequence = 3,
    this.existingMeasures,
    this.proposedMeasures,
    this.responsiblePerson,
    this.imageUrls = const [],
    this.status = 'aktiv',
    this.reviewDate,
    this.createdAt,
    this.templateKey,
    this.scenarioCategory,
    this.avvikBoosted = false,
    this.avvikSignalCount = 0,
    this.avvikLastSignalAt,
    this.linkedTicketCategory,
    this.creatorName,
    this.responsiblePersonName,
  });

  factory RiskAssessment.fromJson(Map<String, dynamic> json) {
    final prob = json['probability'] as int? ?? 3;
    final cons = json['consequence'] as int? ?? 3;
    return RiskAssessment(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      departmentId: json['department_id'] as String?,
      createdBy: json['created_by'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      area: json['area'] as String?,
      probability: prob,
      consequence: cons,
      riskScore: json['risk_score'] as int?,
      initialProbability: json['initial_probability'] as int? ?? prob,
      initialConsequence: json['initial_consequence'] as int? ?? cons,
      residualProbability: json['residual_probability'] as int? ?? prob,
      residualConsequence: json['residual_consequence'] as int? ?? cons,
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
      templateKey: json['template_key'] as String?,
      scenarioCategory: json['scenario_category'] as String?,
      avvikBoosted: json['avvik_boosted'] as bool? ?? false,
      avvikSignalCount: json['avvik_signal_count'] as int? ?? 0,
      avvikLastSignalAt: json['avvik_last_signal_at'] != null
          ? DateTime.parse(json['avvik_last_signal_at'] as String)
          : null,
      linkedTicketCategory: json['linked_ticket_category'] as String?,
      creatorName: json['creator'] != null
          ? json['creator']['full_name'] as String?
          : json['profiles'] != null
              ? json['profiles']['full_name'] as String?
              : null,
      responsiblePersonName: json['responsible'] != null
          ? json['responsible']['full_name'] as String?
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
        'probability': initialProbability,
        'consequence': initialConsequence,
        'initial_probability': initialProbability,
        'initial_consequence': initialConsequence,
        'residual_probability': residualProbability,
        'residual_consequence': residualConsequence,
        'existing_measures': existingMeasures,
        'proposed_measures': proposedMeasures,
        'responsible_person': responsiblePerson,
        'responsible_person': responsiblePerson,
        'image_urls': imageUrls,
        'template_key': templateKey,
        'scenario_category': scenarioCategory,
      };

  int get calculatedRiskScore => riskScore ?? (probability * consequence);

  int get initialRiskScore => initialProbability * initialConsequence;

  int get residualRiskScore => residualProbability * residualConsequence;

  String riskLevelForScore(int score) {
    if (score <= 4) return 'Lav';
    if (score <= 9) return 'Middels';
    if (score <= 14) return 'Høy';
    if (score <= 19) return 'Kritisk';
    return 'Ekstrem';
  }

  String get riskLevel => riskLevelForScore(calculatedRiskScore);

  String get initialRiskLevel => riskLevelForScore(initialRiskScore);

  String get residualRiskLevel => riskLevelForScore(residualRiskScore);

  bool get isHighRisk => calculatedRiskScore >= 15;
}
