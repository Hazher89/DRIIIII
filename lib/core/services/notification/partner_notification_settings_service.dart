import '../../../models/partner_notification_settings.dart';
import '../supabase_service.dart';

class PartnerNotificationSettingsService {
  PartnerNotificationSettingsService._();

  static Future<PartnerNotificationSettings> fetch(String companyId) async {
    final row = await SupabaseService.client
        .from('company_partner_notification_settings')
        .select()
        .eq('company_id', companyId)
        .maybeSingle();
    if (row == null) return PartnerNotificationSettings(companyId: companyId);
    return PartnerNotificationSettings.fromJson(Map<String, dynamic>.from(row));
  }

  static Future<void> save(PartnerNotificationSettings s, String updatedBy) async {
    await SupabaseService.client
        .from('company_partner_notification_settings')
        .upsert({
      'company_id': s.companyId,
      'route_ack_reminder_hours': s.routeAckReminderHours,
      'ch_partner_route': s.chPartnerRoute.dbValue,
      'ch_partner_route_owner': s.chPartnerRouteOwner.dbValue,
      'ch_partner_meeting': s.chPartnerMeeting.dbValue,
      'ch_partner_portal': s.chPartnerPortal.dbValue,
      'ch_partner_compose': s.chPartnerCompose.dbValue,
      'ch_vehicle_rental': s.chVehicleRental.dbValue,
      'ch_vehicle_rental_status': s.chVehicleRentalStatus.dbValue,
      'ch_partner_general': s.chPartnerGeneral.dbValue,
      'ch_partner_document': s.chPartnerDocument.dbValue,
      'ch_partner_document_folder': s.chPartnerDocumentFolder.dbValue,
      'ch_partner_shared_routine': s.chPartnerSharedRoutine.dbValue,
      'ch_partner_route_reminder': s.chPartnerRouteReminder.dbValue,
      'ch_partner_route_rejected': s.chPartnerRouteRejected.dbValue,
      'ch_partner_route_accepted': s.chPartnerRouteAccepted.dbValue,
      'ch_partner_weekly_summary': s.chPartnerWeeklySummary.dbValue,
      'ch_partner_mass_route': s.chPartnerMassRoute.dbValue,
      'ch_partner_vehicle_inactive': s.chPartnerVehicleInactive.dbValue,
      'updated_by': updatedBy,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}
