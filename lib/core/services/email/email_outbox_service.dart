import '../supabase_service.dart';

/// Utgående e-post-kø (Domeneshop SMTP worker).
class EmailOutboxService {
  EmailOutboxService._();

  static Future<Map<String, dynamic>?> flushEmailOutbox() async {
    try {
      final res = await SupabaseService.client.functions.invoke(
        'send-email-outbox',
      );
      if (res.data is Map<String, dynamic>) {
        return res.data as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
