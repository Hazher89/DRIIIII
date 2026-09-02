import '../../../models/user_profile.dart';
import '../supabase_service.dart';
import 'assistant_access_policy.dart';

/// Kontinuerlig læring: assistenten husker fakta/hendelser per bedrift.
class AssistantMemoryEntry {
  const AssistantMemoryEntry({
    required this.id,
    required this.companyId,
    required this.kind,
    required this.content,
    this.subjectKey,
    this.subjectUserId,
    this.visibility = 'company',
    this.sourceQuery,
    this.createdAt,
  });

  final String id;
  final String companyId;
  final String kind;
  final String content;
  final String? subjectKey;
  final String? subjectUserId;
  final String visibility;
  final String? sourceQuery;
  final DateTime? createdAt;

  factory AssistantMemoryEntry.fromJson(Map<String, dynamic> json) {
    return AssistantMemoryEntry(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      kind: json['kind'] as String? ?? 'fact',
      content: json['content'] as String? ?? '',
      subjectKey: json['subject_key'] as String?,
      subjectUserId: json['subject_user_id'] as String?,
      visibility: json['visibility'] as String? ?? 'company',
      sourceQuery: json['source_query'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}

class AssistantMemoryService {
  AssistantMemoryService._();

  /// Lagre et lært faktum (rute, fraværssammendrag, Q&A).
  static Future<void> remember({
    required String companyId,
    required String kind,
    required String content,
    String? subjectKey,
    String? subjectUserId,
    String visibility = 'company',
    String? sourceQuery,
  }) async {
    if (!SupabaseService.isConfigured) return;
    final text = content.trim();
    if (text.isEmpty) return;
    try {
      await SupabaseService.client.from('assistant_memory').insert({
        'company_id': companyId,
        'kind': kind,
        'content': text.length > 4000 ? text.substring(0, 4000) : text,
        if (subjectKey != null) 'subject_key': subjectKey,
        if (subjectUserId != null) 'subject_user_id': subjectUserId,
        'visibility': visibility,
        if (sourceQuery != null) 'source_query': sourceQuery,
        'created_by': SupabaseService.client.auth.currentUser?.id,
      });
    } catch (_) {
      // Tabell kan mangle før migrering — ikke krasj chatten.
    }
  }

  /// Hent nylige minner filtrert etter GDPR-tilgang.
  static Future<List<AssistantMemoryEntry>> recall({
    required UserProfile viewer,
    String? subjectKey,
    int limit = 24,
  }) async {
    if (!SupabaseService.isConfigured || viewer.companyId == null) {
      return const [];
    }
    try {
      var query = SupabaseService.client
          .from('assistant_memory')
          .select()
          .eq('company_id', viewer.companyId!);
      if (subjectKey != null) {
        query = query.eq('subject_key', subjectKey);
      }
      final data = await query
          .order('created_at', ascending: false)
          .limit(limit * 3) as List<dynamic>;
      final tier = await AssistantAccessPolicy.tierFor(viewer);
      final out = <AssistantMemoryEntry>[];
      for (final raw in data) {
        final e = AssistantMemoryEntry.fromJson(
          Map<String, dynamic>.from(raw as Map),
        );
        if (!_visibleTo(viewer, tier, e)) continue;
        out.add(e);
        if (out.length >= limit) break;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static bool _visibleTo(
    UserProfile viewer,
    AssistantAccessTier tier,
    AssistantMemoryEntry e,
  ) {
    switch (e.visibility) {
      case 'company':
        return true;
      case 'principals':
        return tier == AssistantAccessTier.principal;
      case 'self':
        return e.subjectUserId == viewer.id ||
            tier == AssistantAccessTier.principal;
      default:
        if (e.visibility.startsWith('user:')) {
          final uid = e.visibility.substring(5);
          return uid == viewer.id || tier == AssistantAccessTier.principal;
        }
        if (e.visibility.startsWith('department:')) {
          if (tier == AssistantAccessTier.principal) return true;
          if (tier != AssistantAccessTier.departmentLeader) return false;
          final deptId = e.visibility.substring('department:'.length);
          // Subject leave events are OK for leaders; exact dept membership
          // is enforced when answering leave Q&A. Allow recall for leaders.
          return deptId.isNotEmpty;
        }
        return tier == AssistantAccessTier.principal;
    }
  }
}
