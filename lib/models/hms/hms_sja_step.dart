class HmsSjaStep {
  final String id;
  final String sjaId;
  final int stepOrder;
  final String operation;
  final String hazard;
  final String measure;
  final int? probability;
  final int? consequence;

  const HmsSjaStep({
    required this.id,
    required this.sjaId,
    required this.stepOrder,
    required this.operation,
    required this.hazard,
    required this.measure,
    this.probability,
    this.consequence,
  });

  factory HmsSjaStep.fromJson(Map<String, dynamic> json) {
    return HmsSjaStep(
      id: json['id'] as String,
      sjaId: json['sja_id'] as String,
      stepOrder: json['step_order'] as int? ?? 1,
      operation: json['operation'] as String,
      hazard: json['hazard'] as String,
      measure: json['measure'] as String,
      probability: json['probability'] as int?,
      consequence: json['consequence'] as int?,
    );
  }

  Map<String, dynamic> toInsertJson({
    required String companyId,
  }) =>
      {
        'sja_id': sjaId,
        'company_id': companyId,
        'step_order': stepOrder,
        'operation': operation,
        'hazard': hazard,
        'measure': measure,
        if (probability != null) 'probability': probability,
        if (consequence != null) 'consequence': consequence,
      };
}

class HmsSjaSignature {
  final String id;
  final String sjaId;
  final String profileId;
  final DateTime signedAt;
  final String method;
  final String? signatureUrl;
  final bool pinVerified;
  final String? profileName;

  const HmsSjaSignature({
    required this.id,
    required this.sjaId,
    required this.profileId,
    required this.signedAt,
    this.method = 'digital',
    this.signatureUrl,
    this.pinVerified = false,
    this.profileName,
  });

  factory HmsSjaSignature.fromJson(Map<String, dynamic> json) {
    return HmsSjaSignature(
      id: json['id'] as String,
      sjaId: json['sja_id'] as String,
      profileId: json['profile_id'] as String,
      signedAt: DateTime.parse(json['signed_at'] as String),
      method: json['method'] as String? ?? 'digital',
      signatureUrl: json['signature_url'] as String?,
      pinVerified: json['pin_verified'] as bool? ?? false,
      profileName: json['profiles'] != null
          ? json['profiles']['full_name'] as String?
          : null,
    );
  }
}
