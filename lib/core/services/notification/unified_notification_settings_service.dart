import '../../../models/notification_channel.dart';
import '../../../models/notification_event_definition.dart';
import '../supabase_service.dart';

/// Leser/skriver varselinnstillinger direkte mot Supabase (sanntid).
class UnifiedNotificationSettingsService {
  UnifiedNotificationSettingsService._();

  static Future<List<NotificationEventDefinition>> fetchEvents(
    String companyId,
  ) async {
    final data = await SupabaseService.client.rpc(
      'get_company_notification_events',
      params: {'p_company_id': companyId},
    ) as List<dynamic>;

    return data
        .map(
          (e) => NotificationEventDefinition.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  static Future<void> setChannel({
    required String companyId,
    required String eventId,
    required NotificationChannel channel,
  }) async {
    await SupabaseService.client.rpc(
      'set_notification_event_channel',
      params: {
        'p_company_id': companyId,
        'p_event_id': eventId,
        'p_channel': channel.dbValue,
      },
    );
  }

  static Future<int> fetchRouteAckReminderMinutes(String companyId) async {
    final row = await SupabaseService.client
        .from('company_partner_notification_settings')
        .select('route_ack_reminder_minutes')
        .eq('company_id', companyId)
        .maybeSingle();
    return row?['route_ack_reminder_minutes'] as int? ?? 1440;
  }

  static Future<void> setRouteAckReminderMinutes({
    required String companyId,
    required int minutes,
  }) async {
    await SupabaseService.client.rpc(
      'set_partner_route_ack_reminder_minutes',
      params: {
        'p_company_id': companyId,
        'p_minutes': minutes,
      },
    );
  }
}
