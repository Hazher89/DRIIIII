class RiskDocumentAttachment {
  final String url;
  final String fileName;
  final String? mimeType;
  final DateTime? uploadedAt;

  const RiskDocumentAttachment({
    required this.url,
    required this.fileName,
    this.mimeType,
    this.uploadedAt,
  });

  bool get isPdf =>
      mimeType == 'application/pdf' || fileName.toLowerCase().endsWith('.pdf');

  factory RiskDocumentAttachment.fromJson(Map<String, dynamic> json) {
    return RiskDocumentAttachment(
      url: json['url'] as String,
      fileName: json['file_name'] as String? ?? 'Dokument',
      mimeType: json['mime_type'] as String?,
      uploadedAt: json['uploaded_at'] != null
          ? DateTime.tryParse(json['uploaded_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'file_name': fileName,
        if (mimeType != null) 'mime_type': mimeType,
        if (uploadedAt != null) 'uploaded_at': uploadedAt!.toIso8601String(),
      };
}

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
  final String? residualMeasures;
  final String? responsiblePerson;
  final List<String> imageUrls;
  final List<RiskDocumentAttachment> documentUrls;
  final String status;
  final DateTime? reviewDate;
  final DateTime? deadline;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? templateKey;
  final String? scenarioCategory;
  final bool avvikBoosted;
  final int avvikSignalCount;
  final DateTime? avvikLastSignalAt;
  final String? linkedTicketCategory;
  final String? hazardSource;
  final String? affectedPersons;
  final String? legalReference;
  final String? evaluationMethod;
  final String? rootCause;
  final String? treatmentNotes;
  final String? reviewNotes;
  final String? isoStandard;
  final String? activityProcess;
  final String? locationDetail;
  final DateTime? treatedAt;
  final String? treatedBy;

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
    this.residualMeasures,
    this.responsiblePerson,
    this.imageUrls = const [],
    this.documentUrls = const [],
    this.status = 'aktiv',
    this.reviewDate,
    this.deadline,
    this.createdAt,
    this.updatedAt,
    this.templateKey,
    this.scenarioCategory,
    this.avvikBoosted = false,
    this.avvikSignalCount = 0,
    this.avvikLastSignalAt,
    this.linkedTicketCategory,
    this.hazardSource,
    this.affectedPersons,
    this.legalReference,
    this.evaluationMethod,
    this.rootCause,
    this.treatmentNotes,
    this.reviewNotes,
    this.isoStandard,
    this.activityProcess,
    this.locationDetail,
    this.treatedAt,
    this.treatedBy,
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
      residualMeasures: json['residual_measures'] as String?,
      responsiblePerson: json['responsible_person'] as String?,
      imageUrls: (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      documentUrls: (json['document_urls'] as List<dynamic>? ?? [])
          .map((e) => RiskDocumentAttachment.fromJson(e as Map<String, dynamic>))
          .toList(),
      status: json['status'] as String? ?? 'aktiv',
      reviewDate: json['review_date'] != null
          ? DateTime.tryParse(json['review_date'] as String)
          : null,
      deadline: json['deadline'] != null
          ? DateTime.tryParse(json['deadline'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      templateKey: json['template_key'] as String?,
      scenarioCategory: json['scenario_category'] as String?,
      avvikBoosted: json['avvik_boosted'] as bool? ?? false,
      avvikSignalCount: json['avvik_signal_count'] as int? ?? 0,
      avvikLastSignalAt: json['avvik_last_signal_at'] != null
          ? DateTime.parse(json['avvik_last_signal_at'] as String)
          : null,
      linkedTicketCategory: json['linked_ticket_category'] as String?,
      hazardSource: json['hazard_source'] as String?,
      affectedPersons: json['affected_persons'] as String?,
      legalReference: json['legal_reference'] as String?,
      evaluationMethod: json['evaluation_method'] as String?,
      rootCause: json['root_cause'] as String?,
      treatmentNotes: json['treatment_notes'] as String?,
      reviewNotes: json['review_notes'] as String?,
      isoStandard: json['iso_standard'] as String?,
      activityProcess: json['activity_process'] as String?,
      locationDetail: json['location_detail'] as String?,
      treatedAt: json['treated_at'] != null
          ? DateTime.tryParse(json['treated_at'] as String)
          : null,
      treatedBy: json['treated_by'] as String?,
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
        'residual_measures': residualMeasures,
        'responsible_person': responsiblePerson,
        'image_urls': imageUrls,
        'document_urls': documentUrls.map((d) => d.toJson()).toList(),
        'status': status,
        'review_date': reviewDate?.toIso8601String().split('T').first,
        'deadline': deadline?.toIso8601String().split('T').first,
        'template_key': templateKey,
        'scenario_category': scenarioCategory,
        'hazard_source': hazardSource,
        'affected_persons': affectedPersons,
        'legal_reference': legalReference,
        'evaluation_method': evaluationMethod,
        'root_cause': rootCause,
        'treatment_notes': treatmentNotes,
        'review_notes': reviewNotes,
        'iso_standard': isoStandard,
        'activity_process': activityProcess,
        'location_detail': locationDetail,
        if (treatedAt != null) 'treated_at': treatedAt!.toIso8601String(),
        if (treatedBy != null) 'treated_by': treatedBy,
      };

  Map<String, dynamic> toUpdateJson() => {
        ...toInsertJson(),
        'probability': initialProbability,
        'consequence': initialConsequence,
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

  int get attachmentCount => imageUrls.length + documentUrls.length;
}
