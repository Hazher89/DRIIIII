enum EquipmentStatus { ok, needsService, broken, retired }

extension EquipmentStatusExtension on EquipmentStatus {
  String get label {
    switch (this) {
      case EquipmentStatus.ok: return 'I orden';
      case EquipmentStatus.needsService: return 'Trenger service';
      case EquipmentStatus.broken: return 'Defekt';
      case EquipmentStatus.retired: return 'Utrangert';
    }
  }
}

class Equipment {
  final String id;
  final String companyId;
  final String name;
  final String? brand;
  final String? model;
  final String? serialNumber;
  final EquipmentStatus status;
  final DateTime? lastService;
  final DateTime? nextService;
  final String? assignedTo;
  final String? departmentId;
  final List<String> imageUrls;
  final DateTime? createdAt;

  const Equipment({
    required this.id,
    required this.companyId,
    required this.name,
    this.brand,
    this.model,
    this.serialNumber,
    required this.status,
    this.lastService,
    this.nextService,
    this.assignedTo,
    this.departmentId,
    this.imageUrls = const [],
    this.createdAt,
  });

  factory Equipment.fromJson(Map<String, dynamic> json) {
    return Equipment(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      name: json['name'] as String,
      brand: json['brand'] as String?,
      model: json['model'] as String?,
      serialNumber: json['serial_number'] as String?,
      status: EquipmentStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => EquipmentStatus.ok,
      ),
      lastService: json['last_service'] != null ? DateTime.parse(json['last_service'] as String) : null,
      nextService: json['next_service'] != null ? DateTime.parse(json['next_service'] as String) : null,
      assignedTo: json['assigned_to'] as String?,
      departmentId: json['department_id'] as String?,
      imageUrls: (json['image_urls'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'company_id': companyId,
    'name': name,
    'brand': brand,
    'model': model,
    'serial_number': serialNumber,
    'status': status.name,
    'last_service': lastService?.toIso8601String(),
    'next_service': nextService?.toIso8601String(),
    'assigned_to': assignedTo,
    'department_id': departmentId,
    'image_urls': imageUrls,
  };
}
