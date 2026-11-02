import '../supabase_service.dart';

/// Tømmer SMS-, e-post- og push-kø (Edge Functions).
class NotificationOutboxService {
  NotificationOutboxService._();

  static DateTime? _lastFlushAt;
  static Future<Map<String, dynamic>>? _inFlight;
  static const _minInterval = Duration(seconds: 20);

  /// Debouncet flush — unngår dobbel Edge Function-kvote ved raske handlinger.
  /// Instant DB-triggere sender allerede; dette er backup/manuell.
  static Future<Map<String, dynamic>> flushAll({bool force = false}) async {
    if (_inFlight != null) return _inFlight!;
    final last = _lastFlushAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _minInterval) {
      return const {
        'sms': {'skipped': true, 'reason': 'debounced'},
        'email': {'skipped': true, 'reason': 'debounced'},
        'push': {'skipped': true, 'reason': 'debounced'},
      };
    }

    final run = _flushNow();
    _inFlight = run;
    try {
      return await run;
    } finally {
      _inFlight = null;
    }
  }

  static Future<Map<String, dynamic>> _flushNow() async {
    _lastFlushAt = DateTime.now();
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
      final res =
          await SupabaseService.client.functions.invoke('send-email-outbox');
      if (res.data is Map) {
        email = Map<String, dynamic>.from(res.data as Map);
      }
    } catch (e) {
      email = {'error': e.toString(), 'sent': 0};
    }

    try {
      final res =
          await SupabaseService.client.functions.invoke('send-push-outbox');
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
