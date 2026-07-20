import '../supabase_service.dart';

/// Tømmer SMS-, e-post- og push-kø (Edge Functions).
class NotificationOutboxService {
  NotificationOutboxService._();

  static Future<Map<String, dynamic>> flushAll() async {
    Map<String, dynamic>? sms;
    Map<String, dynamic>? email;
    Map<String, dynamic>? push;

    try {
      final res = await SupabaseService.client.functions.invoke('send-sms-outbox');
      if (res.data is Map) {
        sms = Map<String, dynamic>.from(res.data as Map);
      }
    } catch (e) {
      sms = {'error': e.toString(), 'sent': 0};
    }

    try {
      final res = await SupabaseService.client.functions.invoke('send-email-outbox');
      if (res.data is Map) {
        email = Map<String, dynamic>.from(res.data as Map);
      }
    } catch (e) {
      email = {'error': e.toString(), 'sent': 0};
    }

    try {
      final res = await SupabaseService.client.functions.invoke('send-push-outbox');
      if (res.data is Map) {
        push = Map<String, dynamic>.from(res.data as Map);
      }
    } catch (e) {
      push = {'error': e.toString(), 'sent': 0};
    }

    return {
      'sms': sms,
      'email': email,
      'push': push,
    };
  }
}
