import '../../core/services/supabase_service.dart';

class LmTrackingSession {
  final String routeId;
  final String publicToken;
  final String companyId;
  final DateTime expiresAt;

  const LmTrackingSession({
    required this.routeId,
    required this.publicToken,
    required this.companyId,
    required this.expiresAt,
  });

  factory LmTrackingSession.fromJson(Map<String, dynamic> json) {
    return LmTrackingSession(
      routeId: json['route_id'] as String,
      publicToken: json['public_token'] as String,
      companyId: json['company_id'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}

class LmTrackingService {
  LmTrackingService._();

  static Future<LmTrackingSession?> fetchByToken(String token) async {
    final row = await SupabaseService.client
        .from('lm_tracking_sessions')
        .select()
        .eq('public_token', token)
        .eq('is_active', true)
        .maybeSingle();
    if (row == null) return null;
    final session = LmTrackingSession.fromJson(row);
    if (session.expiresAt.isBefore(DateTime.now())) return null;
    return session;
  }

  static Future<String?> getPublicUrl(String routeId) async {
    final row = await SupabaseService.client
        .from('lm_tracking_sessions')
        .select('public_token')
        .eq('route_id', routeId)
        .eq('is_active', true)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return row['public_token'] as String?;
  }

  static Future<Map<String, dynamic>?> publicTrackingPayload(String token) async {
    try {
      final res = await SupabaseService.client.rpc('lm_public_tracking', params: {'p_token': token});
      if (res == null) return null;
      return Map<String, dynamic>.from(res as Map);
    } catch (_) {
      return null;
    }
  }
}
