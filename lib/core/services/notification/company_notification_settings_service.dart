import '../../../models/company_notification_settings.dart';
import '../../../models/notification_channel.dart';
import '../supabase_service.dart';

class CompanyNotificationSettingsService {
  CompanyNotificationSettingsService._();

  static Future<CompanyNotificationSettings> fetch(String companyId) async {
    final employee = await SupabaseService.client
        .from('company_sms_settings')
        .select()
        .eq('company_id', companyId)
        .maybeSingle();

    final partner = await SupabaseService.client
        .from('company_partner_notification_settings')
        .select()
        .eq('company_id', companyId)
        .maybeSingle();

    final empMap = employee != null
        ? Map<String, dynamic>.from(employee)
        : {'company_id': companyId};

    return CompanyNotificationSettings.fromJson(
      empMap,
      partner != null ? Map<String, dynamic>.from(partner) : null,
    );
  }

  static Future<void> save(
    CompanyNotificationSettings s,
    String updatedBy,
  ) async {
    final now = DateTime.now().toIso8601String();
    await SupabaseService.client.from('company_sms_settings').upsert({
      'company_id': s.companyId,
      'ch_absence_request': s.chAbsenceRequest.dbValue,
      'ch_absence_decision': s.chAbsenceDecision.dbValue,
      'ch_ticket_new': s.chTicketNew.dbValue,
      'ch_ticket_status': s.chTicketStatus.dbValue,
      'ch_ticket_critical': s.chTicketCritical.dbValue,
      'ch_equipment': s.chEquipment.dbValue,
      'ch_user_approval': s.chUserApproval.dbValue,
      'ch_general': s.chGeneral.dbValue,
      'sms_absence_request': s.chAbsenceRequest != NotificationChannel.none,
      'sms_absence_decision': s.chAbsenceDecision != NotificationChannel.none,
      'sms_ticket_new': s.chTicketNew != NotificationChannel.none,
      'sms_ticket_status': s.chTicketStatus != NotificationChannel.none,
      'sms_ticket_critical': s.chTicketCritical != NotificationChannel.none,
      'sms_equipment': s.chEquipment != NotificationChannel.none,
      'sms_user_approval': s.chUserApproval != NotificationChannel.none,
      'sms_general': s.chGeneral != NotificationChannel.none,
      'updated_by': updatedBy,
      'updated_at': now,
    });

    await SupabaseService.client
        .from('company_partner_notification_settings')
        .upsert({
      'company_id': s.companyId,
      'ch_partner_route': s.chPartnerRoute.dbValue,
      'ch_partner_route_owner': s.chPartnerRouteOwner.dbValue,
      'ch_partner_meeting': s.chPartnerMeeting.dbValue,
      'ch_partner_portal': s.chPartnerPortal.dbValue,
      'ch_partner_compose': s.chPartnerCompose.dbValue,
      'ch_vehicle_rental': s.chVehicleRental.dbValue,
      'ch_vehicle_rental_status': s.chVehicleRentalStatus.dbValue,
      'ch_partner_general': s.chPartnerGeneral.dbValue,
      'updated_by': updatedBy,
      'updated_at': now,
    });
  }
}
