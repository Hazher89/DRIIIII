class PartnerDriverDeviation {
  const PartnerDriverDeviation({
    required this.id,
    required this.companyId,
    required this.partnerId,
    required this.reportedBy,
    required this.routeDate,
    required this.comment,
    required this.status,
    required this.createdAt,
    this.partnerVehicleId,
    this.routeShareId,
    this.customerName,
    this.freightUnit,
    this.customerRef,
    this.orderRef,
    this.reporterName,
    this.imageUrls = const [],
    this.videoUrls = const [],
  });

  final String id;
  final String companyId;
  final String partnerId;
  final String? partnerVehicleId;
  final String? routeShareId;
  final String reportedBy;
  final DateTime routeDate;
  final String? customerName;
  final String? freightUnit;
  final String? customerRef;
  final String? orderRef;
  final String? reporterName;
  final String comment;
  final List<String> imageUrls;
  final List<String> videoUrls;
  final String status;
  final DateTime createdAt;

  String get reporterLabel {
    final name = reporterName?.trim() ?? '';
    return name.isEmpty ? 'Ukjent' : name;
  }

  factory PartnerDriverDeviation.fromJson(Map<String, dynamic> json) {
    return PartnerDriverDeviation(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      partnerId: json['partner_id'] as String,
      partnerVehicleId: json['partner_vehicle_id'] as String?,
      routeShareId: json['route_share_id'] as String?,
      reportedBy: json['reported_by'] as String,
      routeDate: DateTime.parse(json['route_date'] as String),
      customerName: json['customer_name'] as String?,
      freightUnit: json['freight_unit'] as String?,
      customerRef: json['customer_ref'] as String?,
      orderRef: json['order_ref'] as String?,
      reporterName: json['reporter_name'] as String?,
      comment: json['comment'] as String,
      imageUrls: _stringList(json['image_urls']),
      videoUrls: _stringList(json['video_urls']),
      status: json['status'] as String? ?? 'open',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value.map((item) => item.toString()).toList(growable: false);
  }
}

class PartnerDriverDeviationAlertSettings {
  const PartnerDriverDeviationAlertSettings({
    required this.companyId,
    this.enabled = true,
    this.emails = const [],
  });

  final String companyId;
  final bool enabled;
  final List<String> emails;

  factory PartnerDriverDeviationAlertSettings.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawEmails = json['emails'];
    return PartnerDriverDeviationAlertSettings(
      companyId: json['company_id'] as String,
      enabled: json['enabled'] as bool? ?? true,
      emails: rawEmails is List
          ? rawEmails.map((item) => item.toString()).toList(growable: false)
          : const [],
    );
  }
}
