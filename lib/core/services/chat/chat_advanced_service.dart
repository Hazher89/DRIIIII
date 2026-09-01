import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_service.dart';

/// Utvidede chat-funksjoner: planlegging, maler, rapporter, tilstedeværelse m.m.
abstract final class ChatAdvancedService {
  static SupabaseClient get _client => SupabaseService.client;

  static String get _uid {
    final id = SupabaseService.currentUser?.id;
    if (id == null) throw StateError('Ikke innlogget');
    return id;
  }

  static Future<void> heartbeat({String? roomId, bool? hideOnline}) async {
    await _client.rpc('chat_heartbeat', params: {
      'p_room_id': roomId,
      'p_hide_online': hideOnline,
    });
  }

  static Future<List<ChatOnlineUser>> fetchOnlineUsers(String roomId) async {
    final rows = await _client.rpc<dynamic>('chat_room_online_users', params: {'p_room_id': roomId});
    if (rows is! List) return const [];
    return rows.map((e) => ChatOnlineUser.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  static Future<void> markDelivered(String messageId) async {
    await _client.rpc('chat_mark_delivered', params: {'p_message_id': messageId});
  }

  static Future<void> pinMessage(String roomId, String messageId) async {
    await _client.rpc('chat_pin_room_message', params: {
      'p_room_id': roomId,
      'p_message_id': messageId,
    });
  }

  static Future<void> unpinMessage(String roomId) async {
    await _client.rpc('chat_unpin_room_message', params: {'p_room_id': roomId});
  }

  static Future<String> reportMessage(String messageId, {String? reason}) async {
    return await _client.rpc<String>('chat_report_message', params: {
      'p_message_id': messageId,
      'p_reason': reason,
    });
  }

  static Future<void> approveMember(String roomId, String userId) async {
    await _client.rpc('chat_approve_room_member', params: {
      'p_room_id': roomId,
      'p_user_id': userId,
    });
  }

  static Future<String> scheduleMessage({
    required String roomId,
    required String body,
    required DateTime scheduledFor,
    String messageType = 'text',
    Map<String, dynamic>? attachment,
    String? replyToId,
    List<String>? mentionIds,
    int? expiresHours,
    String? translatedBody,
  }) async {
    return await _client.rpc<String>('chat_schedule_message', params: {
      'p_room_id': roomId,
      'p_body': body,
      'p_scheduled_for': scheduledFor.toUtc().toIso8601String(),
      'p_message_type': messageType,
      'p_attachment': attachment,
      'p_reply_to_id': replyToId,
      'p_mention_ids': mentionIds,
      'p_expires_hours': expiresHours,
      'p_translated_body': translatedBody,
    });
  }

  static Future<void> processScheduled() async {
    await _client.rpc('chat_process_scheduled_messages');
  }

  static Future<String> createSubgroup({
    required String parentRoomId,
    required String title,
  }) async {
    return await _client.rpc<String>('chat_create_subgroup', params: {
      'p_parent_room_id': parentRoomId,
      'p_title': title,
      'p_member_ids': <String>[],
    });
  }

  static Future<Map<String, dynamic>> fetchStats({int days = 30}) async {
    final raw = await _client.rpc<dynamic>('chat_superadmin_stats', params: {'p_days': days});
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  static Future<List<ChatMessageTemplate>> fetchTemplates() async {
    final rows = await _client
        .from('chat_message_templates')
        .select('id, title, body, sort_order')
        .eq('is_active', true)
        .order('sort_order');
    return (rows as List)
        .map((e) => ChatMessageTemplate.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<void> saveTemplate({required String title, required String body}) async {
    final co = SupabaseService.currentUser?.id;
    if (co == null) return;
    await _client.from('chat_message_templates').insert({
      'company_id': await _companyId(),
      'title': title,
      'body': body,
      'created_by': _uid,
    });
  }

  static Future<String?> _companyId() async {
    final row = await _client.from('profiles').select('company_id').eq('id', _uid).maybeSingle();
    return row?['company_id'] as String?;
  }

  static Future<void> updateRoomSettings({
    required String roomId,
    String? welcomeMessage,
    String? rulesText,
    bool? requireApproval,
  }) async {
    final patch = <String, dynamic>{'updated_at': DateTime.now().toUtc().toIso8601String()};
    if (welcomeMessage != null) patch['welcome_message'] = welcomeMessage;
    if (rulesText != null) patch['rules_text'] = rulesText;
    if (requireApproval != null) patch['require_member_approval'] = requireApproval;
    await _client.from('chat_rooms').update(patch).eq('id', roomId);
  }
}

class ChatOnlineUser {
  const ChatOnlineUser({required this.userId, required this.fullName, required this.isOnline});
  final String userId;
  final String fullName;
  final bool isOnline;

  factory ChatOnlineUser.fromJson(Map<String, dynamic> json) => ChatOnlineUser(
        userId: json['user_id'] as String,
        fullName: (json['full_name'] as String?) ?? 'Bruker',
        isOnline: json['is_online'] as bool? ?? false,
      );
}

class ChatMessageTemplate {
  const ChatMessageTemplate({required this.id, required this.title, required this.body});
  final String id;
  final String title;
  final String body;

  factory ChatMessageTemplate.fromJson(Map<String, dynamic> json) => ChatMessageTemplate(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
      );
}

/// Parser @navn eller @[uuid] i tekst.
abstract final class ChatMentionParser {
  static final _uuidMention = RegExp(r'@\[([0-9a-f-]{36})\]', caseSensitive: false);
  static final _atWord = RegExp(r'@(\S+)');

  static List<String> extractMentionIds(String text, List<ChatMentionCandidate> candidates) {
    final ids = <String>{};
    for (final m in _uuidMention.allMatches(text)) {
      ids.add(m.group(1)!);
    }
    for (final m in _atWord.allMatches(text)) {
      final word = m.group(1)!.toLowerCase();
      for (final c in candidates) {
        if (c.label.toLowerCase().startsWith(word) || c.label.toLowerCase().split(' ').first == word) {
          ids.add(c.userId);
        }
      }
    }
    return ids.toList();
  }

  static String highlightMentions(String text) => text;
}

class ChatMentionCandidate {
  const ChatMentionCandidate({required this.userId, required this.label});
  final String userId;
  final String label;
}
