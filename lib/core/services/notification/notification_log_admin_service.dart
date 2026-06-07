import '../supabase_service.dart';

class NotificationLogClearResult {
  final int smsDeleted;
  final int emailDeleted;
  final int auditDeleted;

  const NotificationLogClearResult({
    required this.smsDeleted,
    required this.emailDeleted,
    required this.auditDeleted,
  });

  factory NotificationLogClearResult.fromJson(Map<String, dynamic> json) {
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return NotificationLogClearResult(
      smsDeleted: n(json['sms_deleted']),
      emailDeleted: n(json['email_deleted']),
      auditDeleted: n(json['audit_deleted']),
    );
  }

  int get total => smsDeleted + emailDeleted + auditDeleted;
}

/// Superadmin / varsel-tilgang: tøm utgående logg.
class NotificationLogAdminService {
  NotificationLogAdminService._();

  static Future<NotificationLogClearResult> clearLogs({
    bool sms = true,
    bool email = true,
    bool audit = true,
    bool queuedOnly = false,
    bool partnerScopeOnly = false,
  }) async {
    final data = await SupabaseService.client.rpc(
      'clear_company_notification_logs',
      params: {
        'p_sms': sms,
        'p_email': email,
        'p_audit': audit,
        'p_only_queued': queuedOnly,
        'p_partner_scope_only': partnerScopeOnly,
      },
    );
    if (data is Map<String, dynamic>) {
      return NotificationLogClearResult.fromJson(data);
    }
    return const NotificationLogClearResult(
      smsDeleted: 0,
      emailDeleted: 0,
      auditDeleted: 0,
    );
  }
}
