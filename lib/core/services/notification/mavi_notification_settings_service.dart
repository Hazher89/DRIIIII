import '../../../models/mavi_notification_settings.dart';
import '../../../models/notification_channel.dart';
import '../supabase_service.dart';

class MaviNotificationSettingsService {
  MaviNotificationSettingsService._();

  static Future<MaviNotificationSettings> fetch(String companyId) async {
    final row = await SupabaseService.client
        .from('company_sms_settings')
        .select()
        .eq('company_id', companyId)
        .maybeSingle();
    if (row == null) return MaviNotificationSettings(companyId: companyId);
    return MaviNotificationSettings.fromJson(Map<String, dynamic>.from(row));
  }

  static Future<void> save(MaviNotificationSettings s, String updatedBy) async {
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
      'ch_partner_route_ack_internal': s.chPartnerRouteAckInternal.dbValue,
      'ch_partner_route_pending_internal': s.chPartnerRoutePendingInternal.dbValue,
      'ch_partner_document_internal': s.chPartnerDocumentInternal.dbValue,
      'ch_sap_route_received': s.chSapRouteReceived.dbValue,
      'ch_partner_rental_internal': s.chPartnerRentalInternal.dbValue,
      'ch_partner_deactivated_internal': s.chPartnerDeactivatedInternal.dbValue,
      'sms_absence_request': s.chAbsenceRequest != NotificationChannel.none,
      'sms_absence_decision': s.chAbsenceDecision != NotificationChannel.none,
      'sms_ticket_new': s.chTicketNew != NotificationChannel.none,
      'sms_ticket_status': s.chTicketStatus != NotificationChannel.none,
      'sms_ticket_critical': s.chTicketCritical != NotificationChannel.none,
      'sms_equipment': s.chEquipment != NotificationChannel.none,
      'sms_user_approval': s.chUserApproval != NotificationChannel.none,
      'sms_general': s.chGeneral != NotificationChannel.none,
      'updated_by': updatedBy,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}
