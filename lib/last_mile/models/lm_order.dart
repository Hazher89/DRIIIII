class LmOrder {
  final String id;
  final String companyId;
  final String source;
  final String? externalRef;
  final String customerName;
  final String? customerPhone;
  final String addressLine;
  final String? postalCode;
  final String? city;
  final double? lat;
  final double? lng;
  final DateTime? timeWindowStart;
  final DateTime? timeWindowEnd;
  final double? weightKg;
  final double? volumeM3;
  final String? serviceNotes;
  final bool requiresInstallation;
  final bool requiresCarryBelt;
  final bool requiresOldAppliancePickup;
  final String status;
  final DateTime createdAt;

  const LmOrder({
    required this.id,
    required this.companyId,
    required this.source,
    this.externalRef,
    required this.customerName,
    this.customerPhone,
    required this.addressLine,
    this.postalCode,
    this.city,
    this.lat,
    this.lng,
    this.timeWindowStart,
    this.timeWindowEnd,
    this.weightKg,
    this.volumeM3,
    this.serviceNotes,
    this.requiresInstallation = false,
    this.requiresCarryBelt = false,
    this.requiresOldAppliancePickup = false,
    this.status = 'pending',
    required this.createdAt,
  });

  factory LmOrder.fromJson(Map<String, dynamic> json) {
    DateTime? dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

    return LmOrder(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      source: json['source'] as String? ?? 'manual',
      externalRef: json['external_ref'] as String?,
      customerName: json['customer_name'] as String,
      customerPhone: json['customer_phone'] as String?,
      addressLine: json['address_line'] as String,
      postalCode: json['postal_code'] as String?,
      city: json['city'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      timeWindowStart: dt(json['time_window_start']),
      timeWindowEnd: dt(json['time_window_end']),
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      volumeM3: (json['volume_m3'] as num?)?.toDouble(),
      serviceNotes: json['service_notes'] as String?,
      requiresInstallation: json['requires_installation'] as bool? ?? false,
      requiresCarryBelt: json['requires_carry_belt'] as bool? ?? false,
      requiresOldAppliancePickup: json['requires_old_appliance_pickup'] as bool? ?? false,
      status: json['status'] as String? ?? 'pending',
      createdAt: dt(json['created_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertJson(String companyId) => {
        'company_id': companyId,
        'source': source,
        if (externalRef != null) 'external_ref': externalRef,
        'customer_name': customerName,
        if (customerPhone != null) 'customer_phone': customerPhone,
        'address_line': addressLine,
        if (postalCode != null) 'postal_code': postalCode,
        if (city != null) 'city': city,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (timeWindowStart != null) 'time_window_start': timeWindowStart!.toUtc().toIso8601String(),
        if (timeWindowEnd != null) 'time_window_end': timeWindowEnd!.toUtc().toIso8601String(),
        if (weightKg != null) 'weight_kg': weightKg,
        if (volumeM3 != null) 'volume_m3': volumeM3,
        if (serviceNotes != null) 'service_notes': serviceNotes,
        'requires_installation': requiresInstallation,
        'requires_carry_belt': requiresCarryBelt,
        'requires_old_appliance_pickup': requiresOldAppliancePickup,
        'status': status,
      };

  bool get hasCoordinates => lat != null && lng != null;
}
