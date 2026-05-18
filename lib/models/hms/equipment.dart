enum EquipmentStatus { ok, needsService, broken, retired }

enum EquipmentCategory {
  electronics,
  truck,
  machine,
  tool,
  vehicle,
  other,
}

enum MaintenanceType {
  service,
  waterFill,
  inspection,
  repair,
  wash,
  storage,
  purchaseNote,
  other,
}

extension EquipmentStatusExtension on EquipmentStatus {
  String get label {
    switch (this) {
      case EquipmentStatus.ok:
        return 'I orden';
      case EquipmentStatus.needsService:
        return 'Trenger service';
      case EquipmentStatus.broken:
        return 'Defekt';
      case EquipmentStatus.retired:
        return 'Utrangert';
    }
  }
}

extension EquipmentCategoryExtension on EquipmentCategory {
  String get label {
    switch (this) {
      case EquipmentCategory.electronics:
        return 'Elektronikk';
      case EquipmentCategory.truck:
        return 'Truck / maskin';
      case EquipmentCategory.machine:
        return 'Maskin';
      case EquipmentCategory.tool:
        return 'Verktøy';
      case EquipmentCategory.vehicle:
        return 'Kjøretøy';
      case EquipmentCategory.other:
        return 'Annet';
    }
  }

  String get dbValue => name == 'waterFill' ? 'water_fill' : name;

  static EquipmentCategory fromDb(String? v) {
    if (v == null) return EquipmentCategory.other;
    if (v == 'electronics') return EquipmentCategory.electronics;
    if (v == 'truck') return EquipmentCategory.truck;
    if (v == 'machine') return EquipmentCategory.machine;
    if (v == 'tool') return EquipmentCategory.tool;
    if (v == 'vehicle') return EquipmentCategory.vehicle;
    return EquipmentCategory.other;
  }
}

extension MaintenanceTypeExtension on MaintenanceType {
  String get label {
    switch (this) {
      case MaintenanceType.service:
        return 'Service';
      case MaintenanceType.waterFill:
        return 'Vann / batteri';
      case MaintenanceType.inspection:
        return 'Kontroll / inspeksjon';
      case MaintenanceType.repair:
        return 'Reparasjon / fikset';
      case MaintenanceType.wash:
        return 'Vasket';
      case MaintenanceType.storage:
        return 'Lagret / parkert';
      case MaintenanceType.purchaseNote:
        return 'Innkjøpsnotat';
      case MaintenanceType.other:
        return 'Annet';
    }
  }

  String get dbValue {
    switch (this) {
      case MaintenanceType.waterFill:
        return 'water_fill';
      case MaintenanceType.purchaseNote:
        return 'purchase_note';
      case MaintenanceType.wash:
        return 'wash';
      case MaintenanceType.storage:
        return 'storage';
      default:
        return name;
    }
  }

  static MaintenanceType fromDb(String? v) {
    switch (v) {
      case 'service':
        return MaintenanceType.service;
      case 'water_fill':
        return MaintenanceType.waterFill;
      case 'inspection':
        return MaintenanceType.inspection;
      case 'repair':
        return MaintenanceType.repair;
      case 'wash':
        return MaintenanceType.wash;
      case 'storage':
        return MaintenanceType.storage;
      case 'purchase_note':
        return MaintenanceType.purchaseNote;
      default:
        return MaintenanceType.other;
    }
  }
}

class Equipment {
  final String id;
  final String companyId;
  final String name;
  final EquipmentCategory category;
  final String? brand;
  final String? model;
  final String? serialNumber;
  final String? description;
  final String? location;
  final String? internalNumber;
  final String? licensePlate;
  final EquipmentStatus status;
  final DateTime? lastService;
  final DateTime? nextService;
  final DateTime? nextWaterCheck;
  final DateTime? nextInspection;
  final DateTime? purchaseDate;
  final double? purchasePrice;
  final DateTime? warrantyUntil;
  final String? supplier;
  final String? assignedTo;
  final String? responsibleUserId;
  final String? registeredBy;
  final String? departmentId;
  final List<String> imageUrls;
  final List<String> receiptUrls;
  final List<String> serviceManualUrls;
  final int maintenanceIntervalDays;
  final int notifyDaysBefore;
  final String? notes;
  final String? truckSubtype;
  final Map<String, dynamic> truckChecklistData;
  final bool controlEnabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final String? responsibleName;
  final String? assignedName;

  const Equipment({
    required this.id,
    required this.companyId,
    required this.name,
    this.category = EquipmentCategory.other,
    this.brand,
    this.model,
    this.serialNumber,
    this.description,
    this.location,
    this.internalNumber,
    this.licensePlate,
    required this.status,
    this.lastService,
    this.nextService,
    this.nextWaterCheck,
    this.nextInspection,
    this.purchaseDate,
    this.purchasePrice,
    this.warrantyUntil,
    this.supplier,
    this.assignedTo,
    this.responsibleUserId,
    this.registeredBy,
    this.departmentId,
    this.imageUrls = const [],
    this.receiptUrls = const [],
    this.serviceManualUrls = const [],
    this.maintenanceIntervalDays = 90,
    this.notifyDaysBefore = 7,
    this.notes,
    this.truckSubtype,
    this.truckChecklistData = const {},
    this.controlEnabled = true,
    this.createdAt,
    this.updatedAt,
    this.responsibleName,
    this.assignedName,
  });

  bool get isTruck =>
      category == EquipmentCategory.truck ||
      category == EquipmentCategory.vehicle;

  bool get isDueSoon {
    final now = DateTime.now();
    final limit = now.add(Duration(days: notifyDaysBefore));
    bool due(DateTime? d) => d != null && !d.isBefore(now) && !d.isAfter(limit);
    return due(nextService) ||
        due(nextWaterCheck) ||
        due(nextInspection) ||
        status == EquipmentStatus.needsService;
  }

  bool get isOverdue {
    final now = DateTime.now();
    bool over(DateTime? d) => d != null && d.isBefore(now);
    return over(nextService) ||
        over(nextWaterCheck) ||
        over(nextInspection) ||
        status == EquipmentStatus.needsService;
  }

  factory Equipment.fromJson(Map<String, dynamic> json) {
    return Equipment(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      name: json['name'] as String,
      category: EquipmentCategoryExtension.fromDb(json['category'] as String?),
      brand: json['brand'] as String?,
      model: json['model'] as String?,
      serialNumber: json['serial_number'] as String?,
      description: json['description'] as String?,
      location: json['location'] as String?,
      internalNumber: json['internal_number'] as String?,
      licensePlate: json['license_plate'] as String?,
      status: EquipmentStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => EquipmentStatus.ok,
      ),
      lastService: _parseDate(json['last_service']),
      nextService: _parseDate(json['next_service']),
      nextWaterCheck: _parseDate(json['next_water_check']),
      nextInspection: _parseDate(json['next_inspection']),
      purchaseDate: _parseDate(json['purchase_date']),
      purchasePrice: (json['purchase_price'] as num?)?.toDouble(),
      warrantyUntil: _parseDate(json['warranty_until']),
      supplier: json['supplier'] as String?,
      assignedTo: json['assigned_to'] as String?,
      responsibleUserId: json['responsible_user_id'] as String?,
      registeredBy: json['registered_by'] as String?,
      departmentId: json['department_id'] as String?,
      imageUrls: _strList(json['image_urls']),
      receiptUrls: _strList(json['receipt_urls']),
      serviceManualUrls: _strList(json['service_manual_urls']),
      maintenanceIntervalDays: json['maintenance_interval_days'] as int? ?? 90,
      notifyDaysBefore: json['notify_days_before'] as int? ?? 7,
      notes: json['notes'] as String?,
      truckSubtype: json['truck_subtype'] as String?,
      truckChecklistData:
          (json['truck_checklist_data'] as Map<String, dynamic>?) ?? {},
      controlEnabled: json['control_enabled'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      responsibleName: json['responsible'] != null
          ? json['responsible']['full_name'] as String?
          : null,
      assignedName: json['assigned'] != null
          ? json['assigned']['full_name'] as String?
          : null,
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static List<String> _strList(dynamic v) =>
      (v as List<dynamic>?)?.map((e) => e as String).toList() ?? [];

  Map<String, dynamic> toJson() => {
        'company_id': companyId,
        'name': name,
        'category': category.name == 'electronics'
            ? 'electronics'
            : category.name,
        'brand': brand,
        'model': model,
        'serial_number': serialNumber,
        'description': description,
        'location': location,
        'internal_number': internalNumber,
        'license_plate': licensePlate,
        'status': status.name,
        'last_service': lastService?.toIso8601String().split('T').first,
        'next_service': nextService?.toIso8601String().split('T').first,
        'next_water_check':
            nextWaterCheck?.toIso8601String().split('T').first,
        'next_inspection':
            nextInspection?.toIso8601String().split('T').first,
        'purchase_date': purchaseDate?.toIso8601String().split('T').first,
        'purchase_price': purchasePrice,
        'warranty_until': warrantyUntil?.toIso8601String().split('T').first,
        'supplier': supplier,
        'assigned_to': assignedTo,
        'responsible_user_id': responsibleUserId,
        'registered_by': registeredBy,
        'department_id': departmentId,
        'image_urls': imageUrls,
        'receipt_urls': receiptUrls,
        'service_manual_urls': serviceManualUrls,
        'maintenance_interval_days': maintenanceIntervalDays,
        'notify_days_before': notifyDaysBefore,
        'notes': notes,
        if (truckSubtype != null) 'truck_subtype': truckSubtype,
        'truck_checklist_data': truckChecklistData,
        'control_enabled': controlEnabled,
      };
}

class EquipmentMaintenanceLog {
  final String id;
  final String companyId;
  final String equipmentId;
  final MaintenanceType type;
  final DateTime performedAt;
  final String? performedBy;
  final DateTime? nextDueAt;
  final double? cost;
  final String? odometerOrHours;
  final String? notes;
  final List<String> documentUrls;
  final DateTime? createdAt;
  final String? performerName;

  const EquipmentMaintenanceLog({
    required this.id,
    required this.companyId,
    required this.equipmentId,
    required this.type,
    required this.performedAt,
    this.performedBy,
    this.nextDueAt,
    this.cost,
    this.odometerOrHours,
    this.notes,
    this.documentUrls = const [],
    this.createdAt,
    this.performerName,
  });

  factory EquipmentMaintenanceLog.fromJson(Map<String, dynamic> json) {
    return EquipmentMaintenanceLog(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      equipmentId: json['equipment_id'] as String,
      type: MaintenanceTypeExtension.fromDb(json['maintenance_type'] as String?),
      performedAt: DateTime.parse(json['performed_at'] as String),
      performedBy: json['performed_by'] as String?,
      nextDueAt: Equipment._parseDate(json['next_due_at']),
      cost: (json['cost'] as num?)?.toDouble(),
      odometerOrHours: json['odometer_or_hours'] as String?,
      notes: json['notes'] as String?,
      documentUrls: Equipment._strList(json['document_urls']),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      performerName: json['performer'] != null
          ? json['performer']['full_name'] as String?
          : null,
    );
  }

  Map<String, dynamic> toInsertJson() => {
        'company_id': companyId,
        'equipment_id': equipmentId,
        'maintenance_type': type.dbValue,
        'performed_at': performedAt.toIso8601String(),
        'performed_by': performedBy,
        'next_due_at': nextDueAt?.toIso8601String().split('T').first,
        'cost': cost,
        'odometer_or_hours': odometerOrHours,
        'notes': notes,
        'document_urls': documentUrls,
      };
}

class EquipmentPurchase {
  final String id;
  final String companyId;
  final String? equipmentId;
  final String itemName;
  final String? serialNumber;
  final DateTime purchasedAt;
  final String? purchasedByUserId;
  final String? assignedToUserId;
  final String? departmentId;
  final String? supplier;
  final String? invoiceNumber;
  final double? amount;
  final List<String> receiptUrls;
  final String? notes;
  final DateTime? createdAt;
  final String? purchaserName;
  final String? assignedName;

  const EquipmentPurchase({
    required this.id,
    required this.companyId,
    this.equipmentId,
    required this.itemName,
    this.serialNumber,
    required this.purchasedAt,
    this.purchasedByUserId,
    this.assignedToUserId,
    this.departmentId,
    this.supplier,
    this.invoiceNumber,
    this.amount,
    this.receiptUrls = const [],
    this.notes,
    this.createdAt,
    this.purchaserName,
    this.assignedName,
  });

  factory EquipmentPurchase.fromJson(Map<String, dynamic> json) {
    return EquipmentPurchase(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      equipmentId: json['equipment_id'] as String?,
      itemName: json['item_name'] as String,
      serialNumber: json['serial_number'] as String?,
      purchasedAt: Equipment._parseDate(json['purchased_at']) ?? DateTime.now(),
      purchasedByUserId: json['purchased_by_user_id'] as String?,
      assignedToUserId: json['assigned_to_user_id'] as String?,
      departmentId: json['department_id'] as String?,
      supplier: json['supplier'] as String?,
      invoiceNumber: json['invoice_number'] as String?,
      amount: (json['amount'] as num?)?.toDouble(),
      receiptUrls: Equipment._strList(json['receipt_urls']),
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      purchaserName: json['purchaser'] != null
          ? json['purchaser']['full_name'] as String?
          : null,
      assignedName: json['assignee'] != null
          ? json['assignee']['full_name'] as String?
          : null,
    );
  }

  Map<String, dynamic> toInsertJson() => {
        'company_id': companyId,
        'equipment_id': equipmentId,
        'item_name': itemName,
        'serial_number': serialNumber,
        'purchased_at': purchasedAt.toIso8601String().split('T').first,
        'purchased_by_user_id': purchasedByUserId,
        'assigned_to_user_id': assignedToUserId,
        'department_id': departmentId,
        'supplier': supplier,
        'invoice_number': invoiceNumber,
        'amount': amount,
        'receipt_urls': receiptUrls,
        'notes': notes,
      };
}

class EquipmentNotificationSettings {
  final String companyId;
  final bool notifyResponsible;
  final bool notifyDepartmentLeader;
  final bool notifySuperadmin;
  final int defaultNotifyDaysBefore;
  final int truckWaterIntervalDays;
  final int truckServiceIntervalDays;

  const EquipmentNotificationSettings({
    required this.companyId,
    this.notifyResponsible = true,
    this.notifyDepartmentLeader = true,
    this.notifySuperadmin = true,
    this.defaultNotifyDaysBefore = 7,
    this.truckWaterIntervalDays = 7,
    this.truckServiceIntervalDays = 90,
  });

  factory EquipmentNotificationSettings.fromJson(Map<String, dynamic> json) {
    return EquipmentNotificationSettings(
      companyId: json['company_id'] as String,
      notifyResponsible: json['notify_responsible'] as bool? ?? true,
      notifyDepartmentLeader:
          json['notify_department_leader'] as bool? ?? true,
      notifySuperadmin: json['notify_superadmin'] as bool? ?? true,
      defaultNotifyDaysBefore: json['default_notify_days_before'] as int? ?? 7,
      truckWaterIntervalDays: json['truck_water_interval_days'] as int? ?? 7,
      truckServiceIntervalDays:
          json['truck_service_interval_days'] as int? ?? 90,
    );
  }

  Map<String, dynamic> toJson() => {
        'company_id': companyId,
        'notify_responsible': notifyResponsible,
        'notify_department_leader': notifyDepartmentLeader,
        'notify_superadmin': notifySuperadmin,
        'default_notify_days_before': defaultNotifyDaysBefore,
        'truck_water_interval_days': truckWaterIntervalDays,
        'truck_service_interval_days': truckServiceIntervalDays,
      };
}

/// Digitalt servicehefte knyttet til truck/maskin.
class EquipmentServiceBook {
  final String id;
  final String companyId;
  final String equipmentId;
  final String bookNumber;
  final String title;
  final DateTime openedAt;
  final String? createdBy;
  final bool isActive;

  const EquipmentServiceBook({
    required this.id,
    required this.companyId,
    required this.equipmentId,
    required this.bookNumber,
    required this.title,
    required this.openedAt,
    this.createdBy,
    this.isActive = true,
  });

  factory EquipmentServiceBook.fromJson(Map<String, dynamic> json) {
    return EquipmentServiceBook(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      equipmentId: json['equipment_id'] as String,
      bookNumber: json['book_number'] as String? ?? '',
      title: json['title'] as String,
      openedAt: DateTime.parse(json['opened_at'] as String),
      createdBy: json['created_by'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class EquipmentServiceReminder {
  final String id;
  final String companyId;
  final String equipmentId;
  final String reminderType;
  final DateTime dueDate;
  final List<String> notifyUserIds;
  final int notifyDaysBefore;
  final DateTime? smsSentAt;
  final String? notes;

  const EquipmentServiceReminder({
    required this.id,
    required this.companyId,
    required this.equipmentId,
    required this.reminderType,
    required this.dueDate,
    this.notifyUserIds = const [],
    this.notifyDaysBefore = 7,
    this.smsSentAt,
    this.notes,
  });

  factory EquipmentServiceReminder.fromJson(Map<String, dynamic> json) {
    final ids = json['notify_user_ids'];
    return EquipmentServiceReminder(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      equipmentId: json['equipment_id'] as String,
      reminderType: json['reminder_type'] as String,
      dueDate: Equipment._parseDate(json['due_date']) ?? DateTime.now(),
      notifyUserIds: ids is List
          ? ids.map((e) => e.toString()).toList()
          : const [],
      notifyDaysBefore: json['notify_days_before'] as int? ?? 7,
      smsSentAt: json['sms_sent_at'] != null
          ? DateTime.parse(json['sms_sent_at'] as String)
          : null,
      notes: json['notes'] as String?,
    );
  }

  String get typeLabel {
    switch (reminderType) {
      case 'water_fill':
        return 'Vann / batteri';
      case 'inspection':
        return 'Inspeksjon';
      default:
        return 'Service';
    }
  }
}

class EquipmentDashboardSummary {
  final int total;
  final int trucks;
  final int electronics;
  final int overdue;
  final int dueSoon;
  final int needsService;

  const EquipmentDashboardSummary({
    this.total = 0,
    this.trucks = 0,
    this.electronics = 0,
    this.overdue = 0,
    this.dueSoon = 0,
    this.needsService = 0,
  });
}
