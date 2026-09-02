import '../supabase_service.dart';

/// Revisjon når Tommy/Nico/Hazher endrer verv eller tilganger.
abstract final class AccessChangeAuditService {
  static Future<void> log({
    required String companyId,
    required String targetProfileId,
    required String action,
    required String summary,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
  }) async {
    if (!SupabaseService.isConfigured) return;
    final actor = SupabaseService.client.auth.currentUser?.id;
    try {
      await SupabaseService.client.from('access_change_audit').insert({
        'company_id': companyId,
        'actor_id': actor,
        'target_profile_id': targetProfileId,
        'action': action,
        'summary': summary.length > 500 ? summary.substring(0, 500) : summary,
        if (oldData != null) 'old_data': oldData,
        if (newData != null) 'new_data': newData,
      });
    } catch (_) {
      // Tabell kan mangle før migrering — ikke blokker lagring.
    }
  }

  static Future<List<AccessChangeAuditEntry>> fetchForTarget({
    required String targetProfileId,
    int limit = 20,
  }) async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final data = await SupabaseService.client
          .from('access_change_audit')
          .select()
          .eq('target_profile_id', targetProfileId)
          .order('created_at', ascending: false)
          .limit(limit) as List<dynamic>;
      return data
          .map((e) => AccessChangeAuditEntry.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

class AccessChangeAuditEntry {
  const AccessChangeAuditEntry({
    required this.id,
    required this.action,
    required this.summary,
    this.actorId,
    this.createdAt,
  });

  final String id;
  final String action;
  final String summary;
  final String? actorId;
  final DateTime? createdAt;

  factory AccessChangeAuditEntry.fromJson(Map<String, dynamic> json) {
    return AccessChangeAuditEntry(
      id: json['id'] as String,
      action: json['action'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      actorId: json['actor_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}
