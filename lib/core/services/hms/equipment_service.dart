import 'dart:typed_data';

import '../../../models/hms/equipment.dart';
import '../../../models/user_profile.dart';
import '../storage/company_file_storage.dart';
import '../supabase_service.dart';

class EquipmentService {
  EquipmentService._();

  static Future<List<Equipment>> fetchAll({
    required String companyId,
    EquipmentCategory? category,
    bool includeRetired = false,
  }) async {
    var q = SupabaseService.client.from('equipment').select('*')
        .eq('company_id', companyId);
    if (category != null) {
      q = q.eq('category', category.name);
    }
    if (!includeRetired) {
      q = q.neq('status', EquipmentStatus.retired.name);
    }
    final data = await q.order('name');
    return (data as List)
        .map((e) => Equipment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<Equipment?> fetchById(String id) async {
    final row = await SupabaseService.client
        .from('equipment')
        .select('*')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return Equipment.fromJson(row);
  }

  static Future<Equipment> save(Equipment item, {String? id}) async {
    final payload = item.toJson();
    if (id != null && id.isNotEmpty) {
      final row = await SupabaseService.client
          .from('equipment')
          .update(payload)
          .eq('id', id)
          .select('*')
          .single();
      return Equipment.fromJson(row);
    }
    final insertPayload = {...payload, if (item.id.isNotEmpty) 'id': item.id};
    final row = await SupabaseService.client
        .from('equipment')
        .insert(insertPayload)
        .select('*')
        .single();
    return Equipment.fromJson(row);
  }

  static Future<String> uploadDocument({
    required String companyId,
    required String fileName,
    required Uint8List bytes,
    String subfolder = 'equipment',
  }) async {
    final path =
        '$companyId/$subfolder/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final stored = await CompanyFileStorage.upload(
      supabaseBucket: 'documents',
      storagePath: path,
      bytes: bytes,
      category: 'hms',
      fileName: fileName,
    );
    return CompanyFileStorage.toStorageReference(stored);
  }

  static Future<List<EquipmentMaintenanceLog>> fetchMaintenanceLogs(
    String equipmentId,
  ) async {
    final data = await SupabaseService.client
        .from('equipment_maintenance_logs')
        .select('*')
        .eq('equipment_id', equipmentId)
        .order('performed_at', ascending: false);
    return (data as List)
        .map((e) =>
            EquipmentMaintenanceLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<EquipmentMaintenanceLog> addMaintenanceLog(
    EquipmentMaintenanceLog log,
  ) async {
    final row = await SupabaseService.client
        .from('equipment_maintenance_logs')
        .insert(log.toInsertJson())
        .select()
        .single();
    return EquipmentMaintenanceLog.fromJson(row);
  }

  static Future<List<EquipmentPurchase>> fetchPurchases({
    required String companyId,
    String? equipmentId,
  }) async {
    var q = SupabaseService.client
        .from('equipment_purchases')
        .select('*')
        .eq('company_id', companyId);
    if (equipmentId != null) {
      q = q.eq('equipment_id', equipmentId);
    }
    final data = await q.order('purchased_at', ascending: false);
    return (data as List)
        .map((e) => EquipmentPurchase.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<EquipmentPurchase> addPurchase(EquipmentPurchase purchase) async {
    final row = await SupabaseService.client
        .from('equipment_purchases')
        .insert(purchase.toInsertJson())
        .select()
        .single();
    return EquipmentPurchase.fromJson(row);
  }

  static Future<EquipmentNotificationSettings> getNotificationSettings(
    String companyId,
  ) async {
    final row = await SupabaseService.client
        .from('equipment_notification_settings')
        .select()
        .eq('company_id', companyId)
        .maybeSingle();
    if (row == null) {
      return EquipmentNotificationSettings(companyId: companyId);
    }
    return EquipmentNotificationSettings.fromJson(row);
  }

  static Future<void> saveNotificationSettings(
    EquipmentNotificationSettings settings,
    String updatedBy,
  ) async {
    await SupabaseService.client.from('equipment_notification_settings').upsert({
      ...settings.toJson(),
      'updated_by': updatedBy,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  static EquipmentDashboardSummary summarize(List<Equipment> items) {
    return EquipmentDashboardSummary(
      total: items.length,
      trucks: items
          .where((e) =>
              e.category == EquipmentCategory.truck ||
              e.category == EquipmentCategory.vehicle)
          .length,
      electronics:
          items.where((e) => e.category == EquipmentCategory.electronics).length,
      overdue: items.where((e) => e.isOverdue).length,
      dueSoon: items.where((e) => e.isDueSoon && !e.isOverdue).length,
      needsService: items
          .where((e) => e.status == EquipmentStatus.needsService)
          .length,
    );
  }

  static Future<EquipmentServiceBook?> fetchServiceBook(String equipmentId) async {
    final row = await SupabaseService.client
        .from('equipment_service_books')
        .select('*')
        .eq('equipment_id', equipmentId)
        .maybeSingle();
    if (row == null) return null;
    return EquipmentServiceBook.fromJson(row);
  }

  static Future<EquipmentServiceBook> ensureServiceBook(String equipmentId) async {
    final id = await SupabaseService.client.rpc(
      'ensure_equipment_service_book',
      params: {'p_equipment_id': equipmentId},
    );
    final book = await SupabaseService.client
        .from('equipment_service_books')
        .select('*')
        .eq('id', id)
        .single();
    return EquipmentServiceBook.fromJson(book);
  }

  static Future<List<EquipmentServiceReminder>> fetchReminders(
    String equipmentId,
  ) async {
    final data = await SupabaseService.client
        .from('equipment_service_reminders')
        .select('*')
        .eq('equipment_id', equipmentId)
        .order('due_date');
    return (data as List)
        .where((e) => (e as Map)['cancelled_at'] == null)
        .map((e) =>
            EquipmentServiceReminder.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<String> scheduleReminder({
    required String equipmentId,
    required String reminderType,
    required DateTime dueDate,
    required List<String> notifyUserIds,
    int notifyDaysBefore = 7,
    String? notes,
  }) async {
    final id = await SupabaseService.client.rpc(
      'schedule_equipment_reminder',
      params: {
        'p_equipment_id': equipmentId,
        'p_reminder_type': reminderType,
        'p_due_date': dueDate.toIso8601String().split('T').first,
        'p_notify_user_ids': notifyUserIds,
        'p_notify_days_before': notifyDaysBefore,
        'p_notes': notes,
      },
    );
    return id as String;
  }

  static Future<int> sendReminderSmsNow(String reminderId) async {
    final n = await SupabaseService.client.rpc(
      'send_equipment_reminder_sms_now',
      params: {'p_reminder_id': reminderId},
    );
    return (n as num).toInt();
  }

  /// Registrer linje i servicehefte + valgfri neste frist og SMS.
  static Future<EquipmentMaintenanceLog> addServiceBookEntry({
    required Equipment equipment,
    required MaintenanceType type,
    required String performedBy,
    String? notes,
    String? odometerOrHours,
    double? cost,
    List<String> documentUrls = const [],
    DateTime? nextDueAt,
    List<String>? smsNotifyUserIds,
    int notifyDaysBefore = 7,
  }) async {
    await ensureServiceBook(equipment.id);

    final log = await addMaintenanceLog(
      EquipmentMaintenanceLog(
        id: '',
        companyId: equipment.companyId,
        equipmentId: equipment.id,
        type: type,
        performedAt: DateTime.now(),
        performedBy: performedBy,
        nextDueAt: nextDueAt,
        cost: cost,
        odometerOrHours: odometerOrHours,
        notes: notes,
        documentUrls: documentUrls,
      ),
    );

    if (nextDueAt != null && smsNotifyUserIds != null && smsNotifyUserIds.isNotEmpty) {
      final rType = type == MaintenanceType.waterFill
          ? 'water_fill'
          : type == MaintenanceType.inspection
              ? 'inspection'
              : 'service';
      await scheduleReminder(
        equipmentId: equipment.id,
        reminderType: rType,
        dueDate: nextDueAt,
        notifyUserIds: smsNotifyUserIds,
        notifyDaysBefore: notifyDaysBefore,
        notes: notes,
      );
    }

    return log;
  }

  static String reminderTypeForMaintenance(MaintenanceType type) {
    switch (type) {
      case MaintenanceType.waterFill:
        return 'water_fill';
      case MaintenanceType.inspection:
        return 'inspection';
      default:
        return 'service';
    }
  }

  /// Utstyr ansatt er ansvarlig for eller har fått tildelt.
  static List<Equipment> filterForEmployee(
    List<Equipment> all,
    UserProfile profile, {
    bool manualsOnly = false,
  }) {
    return all
        .where((e) =>
            e.responsibleUserId == profile.id ||
            e.assignedTo == profile.id)
        .toList();
  }
}
