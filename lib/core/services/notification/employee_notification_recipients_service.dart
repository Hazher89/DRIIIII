import '../../../models/notification_channel.dart';
import '../../../models/notification_recipient_row.dart';
import '../supabase_service.dart';

class EmployeeNotificationRecipientsService {
  EmployeeNotificationRecipientsService._();

  static Future<List<NotificationRecipientRow>> fetchMatrix(
    String companyId,
  ) async {
    final data = await SupabaseService.client.rpc(
      'get_company_notification_recipient_matrix',
      params: {'p_company_id': companyId},
    ) as List<dynamic>;

    return data
        .map(
          (e) => NotificationRecipientRow.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
  }

  static Future<void> setSubscription({
    required String companyId,
    required String profileId,
    required String eventId,
    required bool subscribed,
    NotificationChannel channel = NotificationChannel.both,
  }) async {
    await SupabaseService.client.rpc(
      'set_profile_notification_subscription',
      params: {
        'p_company_id': companyId,
        'p_profile_id': profileId,
        'p_event_id': eventId,
        'p_subscribed': subscribed,
        'p_channel': channel.dbValue,
      },
    );
  }

  static Future<int> resetSubscriptions({
    required String companyId,
    String? profileId,
    String? eventId,
  }) async {
    final result = await SupabaseService.client.rpc(
      'reset_profile_notification_subscriptions',
      params: {
        'p_company_id': companyId,
        'p_profile_id': profileId,
        'p_event_id': eventId,
      },
    );
    return result as int? ?? 0;
  }
}
