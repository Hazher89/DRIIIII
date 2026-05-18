import '../supabase_service.dart';

class CompanySmsSettings {
  final String companyId;
  final bool smsAbsenceRequest;
  final bool smsAbsenceDecision;
  final bool smsTicketNew;
  final bool smsTicketStatus;
  final bool smsTicketCritical;
  final bool smsEquipment;
  final bool smsGeneral;

  const CompanySmsSettings({
    required this.companyId,
    this.smsAbsenceRequest = true,
    this.smsAbsenceDecision = true,
    this.smsTicketNew = true,
    this.smsTicketStatus = true,
    this.smsTicketCritical = true,
    this.smsEquipment = true,
    this.smsGeneral = true,
  });

  factory CompanySmsSettings.fromJson(Map<String, dynamic> json) {
    return CompanySmsSettings(
      companyId: json['company_id'] as String,
      smsAbsenceRequest: json['sms_absence_request'] as bool? ?? true,
      smsAbsenceDecision: json['sms_absence_decision'] as bool? ?? true,
      smsTicketNew: json['sms_ticket_new'] as bool? ?? true,
      smsTicketStatus: json['sms_ticket_status'] as bool? ?? true,
      smsTicketCritical: json['sms_ticket_critical'] as bool? ?? true,
      smsEquipment: json['sms_equipment'] as bool? ?? true,
      smsGeneral: json['sms_general'] as bool? ?? true,
    );
  }

  CompanySmsSettings copyWith({
    bool? smsAbsenceRequest,
    bool? smsAbsenceDecision,
    bool? smsTicketNew,
    bool? smsTicketStatus,
    bool? smsTicketCritical,
    bool? smsEquipment,
    bool? smsGeneral,
  }) {
    return CompanySmsSettings(
      companyId: companyId,
      smsAbsenceRequest: smsAbsenceRequest ?? this.smsAbsenceRequest,
      smsAbsenceDecision: smsAbsenceDecision ?? this.smsAbsenceDecision,
      smsTicketNew: smsTicketNew ?? this.smsTicketNew,
      smsTicketStatus: smsTicketStatus ?? this.smsTicketStatus,
      smsTicketCritical: smsTicketCritical ?? this.smsTicketCritical,
      smsEquipment: smsEquipment ?? this.smsEquipment,
      smsGeneral: smsGeneral ?? this.smsGeneral,
    );
  }

  Map<String, dynamic> toJson() => {
        'company_id': companyId,
        'sms_absence_request': smsAbsenceRequest,
        'sms_absence_decision': smsAbsenceDecision,
        'sms_ticket_new': smsTicketNew,
        'sms_ticket_status': smsTicketStatus,
        'sms_ticket_critical': smsTicketCritical,
        'sms_equipment': smsEquipment,
        'sms_general': smsGeneral,
      };
}

class CompanySmsSettingsService {
  CompanySmsSettingsService._();

  static Future<CompanySmsSettings> fetch(String companyId) async {
    final row = await SupabaseService.client
        .from('company_sms_settings')
        .select()
        .eq('company_id', companyId)
        .maybeSingle();
    if (row == null) return CompanySmsSettings(companyId: companyId);
    return CompanySmsSettings.fromJson(row);
  }

  static Future<void> save(CompanySmsSettings s, String updatedBy) async {
    await SupabaseService.client.from('company_sms_settings').upsert({
      ...s.toJson(),
      'updated_by': updatedBy,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}
