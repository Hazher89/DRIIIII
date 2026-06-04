import '../../../models/notification_audit_entry.dart';
import '../supabase_service.dart';

class NotificationAuditService {
  NotificationAuditService._();

  static Future<List<NotificationAuditEntry>> fetch({
    int limit = 50,
    int offset = 0,
    String? channel,
    String? status,
    String? category,
    bool? partnerScope,
    DateTime? fromDate,
    DateTime? toDate,
    String? search,
    bool excludeDismissed = false,
  }) async {
    final data = await SupabaseService.client.rpc(
      'list_notification_audit',
      params: {
        'p_limit': limit,
        'p_offset': offset,
        'p_channel': channel,
        'p_status': status,
        'p_category': category,
        'p_partner_scope': partnerScope,
        'p_from_date': fromDate?.toUtc().toIso8601String(),
        'p_to_date': toDate != null
            ? DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59)
                .toUtc()
                .toIso8601String()
            : null,
        'p_search': search?.trim().isEmpty == true ? null : search?.trim(),
        'p_exclude_dismissed': excludeDismissed,
      },
    );
    return (data as List)
        .map((e) => NotificationAuditEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
