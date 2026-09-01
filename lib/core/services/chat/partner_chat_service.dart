import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/chat/chat_models.dart';
import '../supabase_service.dart';
import 'chat_unread_service.dart';

/// Partner ↔ MAVI chat — rom, meldinger, vedlegg, grupper, arkiv, realtime.
abstract final class PartnerChatService {
  static SupabaseClient get _client => SupabaseService.client;
  static const _mediaBucket = 'chat-media';

  static String get _uid {
    final id = SupabaseService.currentUser?.id;
    if (id == null) throw StateError('Ikke innlogget');
    return id;
  }

  static Future<List<ChatRoom>> fetchMyRooms({bool archived = false}) async {
    if (SupabaseService.currentUser?.id == null) return const [];

    final uid = _uid;
    final rows = await _client
        .from('chat_rooms')
        .select(
          'id, company_id, room_type, title, partner_id, last_message_at, last_message_preview, '
          'chat_user_room_prefs!left(archived_at, pinned_at, muted_until, user_id)',
        )
        .order('last_message_at', ascending: false, nullsFirst: false);

    final rooms = <ChatRoom>[];
    for (final raw in rows as List) {
      final map = Map<String, dynamic>.from(raw as Map);
      final prefs = map['chat_user_room_prefs'];
      if (prefs is List) {
        map['chat_user_room_prefs'] = prefs.where((p) {
          final m = p as Map;
          return m['user_id'] == uid;
        }).toList();
      }
      final room = ChatRoom.fromJson(map);
      if (room.isArchived == archived) rooms.add(room);
    }

    final unread = await fetchUnreadByRoom();
    for (var i = 0; i < rooms.length; i++) {
      final n = unread[rooms[i].id] ?? 0;
      if (n > 0) {
        rooms[i] = ChatRoom(
          id: rooms[i].id,
          companyId: rooms[i].companyId,
          roomType: rooms[i].roomType,
          title: rooms[i].title,
          partnerId: rooms[i].partnerId,
          lastMessageAt: rooms[i].lastMessageAt,
          lastMessagePreview: rooms[i].lastMessagePreview,
          unreadCount: n,
          isArchived: rooms[i].isArchived,
          isPinned: rooms[i].isPinned,
          isMuted: rooms[i].isMuted,
        );
      }
    }

    rooms.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final at = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });

    return rooms;
  }

  static Future<Map<String, int>> fetchUnreadByRoom() async {
    if (SupabaseService.currentUser?.id == null) return const {};
    final rows = await _client.rpc<dynamic>('chat_my_unread_by_room');
    if (rows is! List) return const {};
    final map = <String, int>{};
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final roomId = row['room_id'] as String?;
      if (roomId == null) continue;
      map[roomId] = (row['unread_count'] as num?)?.toInt() ?? 0;
    }
    return map;
  }

  static Future<int> fetchTotalUnread() async {
    if (SupabaseService.currentUser?.id == null) return 0;
    final n = await _client.rpc<num>('chat_total_unread_count');
    return n.toInt();
  }

  static Future<ChatRoom?> fetchRoomById(String roomId) async {
    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return null;
    final row = await _client
        .from('chat_rooms')
        .select(
          'id, company_id, room_type, title, partner_id, last_message_at, last_message_preview, '
          'chat_user_room_prefs!left(archived_at, pinned_at, muted_until, user_id)',
        )
        .eq('id', roomId)
        .maybeSingle();
    if (row == null) return null;
    final map = Map<String, dynamic>.from(row);
    final prefs = map['chat_user_room_prefs'];
    if (prefs is List) {
      map['chat_user_room_prefs'] = prefs.where((p) {
        final m = p as Map;
        return m['user_id'] == uid;
      }).toList();
    }
    return ChatRoom.fromJson(map);
  }

  static Future<List<ChatMessage>> fetchMessages(
    String roomId, {
    int limit = 80,
    DateTime? before,
  }) async {
    var filter = _client
        .from('chat_messages')
        .select(
          'id, room_id, sender_id, body, message_type, created_at, is_edited, deleted_at, '
          'moderation_state, reply_to_id, chat_message_attachments(id, storage_path, mime_type, file_name, byte_size, width, height, duration_ms)',
        )
        .eq('room_id', roomId);

    if (before != null) {
      filter = filter.lt('created_at', before.toUtc().toIso8601String());
    }

    final rows = await filter.order('created_at', ascending: false).limit(limit);
    final messages = (rows as List)
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList()
        .reversed
        .toList();

    await _attachSenderNames(messages);
    _attachReplyPreviews(messages);
    await _signAttachmentUrls(messages);
    return messages;
  }

  static void _attachReplyPreviews(List<ChatMessage> messages) {
    final byId = {for (final m in messages) m.id: m};
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (m.replyToId != null && byId.containsKey(m.replyToId)) {
        messages[i] = m.copyWith(replyTo: byId[m.replyToId]);
      }
    }
  }

  static Future<void> _attachSenderNames(List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    final ids = messages.map((m) => m.senderId).toSet().toList();
    final rows = await _client.from('profiles').select('id, full_name').inFilter('id', ids);
    final names = <String, String>{
      for (final r in rows as List)
        (r as Map)['id'] as String: ((r)['full_name'] as String?)?.trim() ?? 'Bruker',
    };
    for (var i = 0; i < messages.length; i++) {
      messages[i] = messages[i].copyWith(senderName: names[messages[i].senderId]);
    }
  }

  static Future<void> _signAttachmentUrls(List<ChatMessage> messages) async {
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (m.attachments.isEmpty) continue;
      final signed = <ChatAttachment>[];
      for (final a in m.attachments) {
        try {
          final url = await _client.storage.from(_mediaBucket).createSignedUrl(a.storagePath, 3600);
          signed.add(a.copyWith(signedUrl: url));
        } catch (_) {
          signed.add(a);
        }
      }
      messages[i] = m.copyWith(attachments: signed);
    }
  }

  static Future<String> sendMessage({
    required String roomId,
    required String body,
    String? replyToId,
    ChatMessageType messageType = ChatMessageType.text,
    Map<String, dynamic>? attachment,
  }) async {
    return await _client.rpc<String>(
      'send_chat_message',
      params: {
        'p_room_id': roomId,
        'p_body': body.trim(),
        'p_reply_to_id': replyToId,
        'p_message_type': messageType.dbValue,
        'p_attachment': attachment,
      },
    );
  }

  static Future<String> uploadAndSendMedia({
    required String roomId,
    required ChatPendingMedia media,
    String caption = '',
    String? replyToId,
  }) async {
    final uid = _uid;
    final ext = media.fileName.contains('.')
        ? media.fileName.split('.').last
        : (media.isVideo ? 'mp4' : 'jpg');
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _client.storage.from(_mediaBucket).uploadBinary(
          path,
          Uint8List.fromList(media.bytes),
          fileOptions: FileOptions(contentType: media.mimeType, upsert: false),
        );

    return sendMessage(
      roomId: roomId,
      body: caption,
      replyToId: replyToId,
      messageType: media.isVideo ? ChatMessageType.video : ChatMessageType.image,
      attachment: {
        'storage_path': path,
        'mime_type': media.mimeType,
        'file_name': media.fileName,
        'byte_size': media.bytes.length,
      },
    );
  }

  static Future<void> setArchived(String roomId, bool archived) async {
    await _client.rpc('chat_set_room_archived', params: {
      'p_room_id': roomId,
      'p_archived': archived,
    });
  }

  static Future<void> setPinned(String roomId, bool pinned) async {
    await _client.rpc('chat_set_room_pinned', params: {
      'p_room_id': roomId,
      'p_pinned': pinned,
    });
  }

  static Future<void> setMuted(String roomId, bool muted, {int? hours}) async {
    await _client.rpc('chat_set_room_muted', params: {
      'p_room_id': roomId,
      'p_muted': muted,
      'p_hours': hours,
    });
  }

  static Future<String> ensureBroadcastRoom(String companyId) async {
    return await _client.rpc<String>(
      'ensure_partner_broadcast_room',
      params: {'p_company_id': companyId},
    );
  }

  static Future<String> createPartnerPrivateChat(String otherUserId) async {
    return await _client.rpc<String>(
      'create_partner_private_chat',
      params: {'p_other_user_id': otherUserId},
    );
  }

  static Future<String> createPartnerGroupChat({
    required List<String> memberIds,
    required String title,
  }) async {
    return await _client.rpc<String>(
      'create_partner_group_chat',
      params: {'p_member_ids': memberIds, 'p_title': title},
    );
  }

  static Future<String> createMaviGroupChat({
    required List<String> memberIds,
    required String title,
  }) async {
    return await _client.rpc<String>(
      'create_mavi_group_chat',
      params: {'p_member_ids': memberIds, 'p_title': title},
    );
  }

  static Future<String> createMaviPartnerDirectChat(String partnerId) async {
    return await _client.rpc<String>(
      'create_mavi_partner_direct_chat',
      params: {'p_partner_id': partnerId},
    );
  }

  static Future<String> superadminCreateMaviGroup({
    required List<String> memberIds,
    required String title,
  }) async {
    return await _client.rpc<String>(
      'chat_superadmin_create_mavi_group',
      params: {'p_member_ids': memberIds, 'p_title': title},
    );
  }

  static Future<String> superadminCreatePartnerGroup({
    required List<String> memberIds,
    required String title,
  }) async {
    return await _client.rpc<String>(
      'chat_superadmin_create_partner_group',
      params: {'p_member_ids': memberIds, 'p_title': title},
    );
  }

  static Future<int> superadminInviteToRoom({
    required String roomId,
    required List<String> userIds,
  }) async {
    final n = await _client.rpc<int>(
      'chat_superadmin_invite_to_room',
      params: {'p_room_id': roomId, 'p_user_ids': userIds},
    );
    return n;
  }

  static Future<List<ChatPartnerDirectoryEntry>> fetchPartnerDirectory() async {
    final data = await _client.rpc<dynamic>('chat_partner_directory');
    if (data is! List) return const [];
    return data
        .map((e) => ChatPartnerDirectoryEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<List<ChatMaviDirectoryEntry>> fetchMaviDirectory(String companyId) async {
    final data = await _client.rpc<dynamic>('chat_mavi_directory');
    if (data is! List) return const [];
    return data
        .map((e) => ChatMaviDirectoryEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<ChatSuperadminDirectory> fetchSuperadminDirectory() async {
    final data = await _client.rpc<Map<String, dynamic>>('chat_superadmin_directory');
    return ChatSuperadminDirectory.fromJson(data);
  }

  static Future<void> partnerBlockUser(String userId, {String? reason}) async {
    await _client.rpc('chat_partner_block_user', params: {
      'p_blocked_user_id': userId,
      'p_reason': reason,
    });
  }

  static Future<void> partnerUnblockUser(String userId) async {
    await _client.rpc('chat_partner_unblock_user', params: {
      'p_blocked_user_id': userId,
    });
  }

  static Future<void> adminBlockUser(String userId, {String? reason, String? roomId}) async {
    await _client.rpc('chat_block_user', params: {
      'p_blocked_user_id': userId,
      'p_reason': reason,
      'p_room_id': roomId,
    });
  }

  static Future<void> adminUnblockUser(String userId, {String? roomId}) async {
    await _client.rpc('chat_unblock_user', params: {
      'p_blocked_user_id': userId,
      'p_room_id': roomId,
    });
  }

  static Future<void> hideMessage(String messageId) async {
    await _client.rpc('chat_hide_message', params: {'p_message_id': messageId});
  }

  static Future<void> deleteOwnMessage(String messageId) async {
    await _client.rpc('chat_delete_own_message', params: {'p_message_id': messageId});
  }

  static Future<List<ChatBlockedUser>> fetchPartnerBlockedUsers() async {
    final rows = await _client.rpc<dynamic>('chat_partner_blocked_list');
    if (rows is! List) return const [];
    return rows
        .map((e) => ChatBlockedUser.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<List<ChatAuditEntry>> fetchModerationAudit({int limit = 50}) async {
    final rows = await _client
        .from('chat_audit_log')
        .select('id, action, room_id, message_id, target_user_id, meta, created_at, actor_id')
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((e) => ChatAuditEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<List<ChatReadReceipt>> fetchReadReceipts(String roomId, String messageId) async {
    final rows = await _client.rpc<dynamic>(
      'chat_message_read_by',
      params: {'p_room_id': roomId, 'p_message_id': messageId},
    );
    if (rows is! List) return const [];
    return rows
        .map((e) => ChatReadReceipt.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static RealtimeChannel subscribeRoom({
    required String roomId,
    required void Function(ChatMessage message) onMessage,
  }) {
    return _client
        .channel('chat_room_$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) async {
            final record = payload.newRecord;
            if (record.isEmpty) return;
            var msg = ChatMessage.fromJson(Map<String, dynamic>.from(record));
            await _attachSenderNames([msg]);
            await _signAttachmentUrls([msg]);
            onMessage(msg);
          },
        )
        ..subscribe();
  }

  static void unsubscribe(RealtimeChannel? channel) {
    if (channel != null) _client.removeChannel(channel);
  }

  static Future<void> markRead(String roomId, String messageId) async {
    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return;
    await _client.from('chat_read_state').upsert({
      'room_id': roomId,
      'user_id': uid,
      'last_read_message_id': messageId,
      'last_read_at': DateTime.now().toUtc().toIso8601String(),
    });
    unawaited(ChatUnreadService.refresh());
  }
}
