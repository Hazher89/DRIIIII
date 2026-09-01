import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/chat/chat_models.dart';
import '../storage/company_file_storage.dart';
import '../storage/storage_file_access.dart';
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
          'moderation_state, reply_to_id, expires_at, translated_body, thread_root_id, '
          'chat_message_attachments(id, storage_path, mime_type, file_name, byte_size, width, height, duration_ms), '
          'chat_message_reactions(emoji, user_id, profiles(full_name))',
        )
        .eq('room_id', roomId);

    if (before != null) {
      filter = filter.lt('created_at', before.toUtc().toIso8601String());
    }

    final rows = await filter.order('created_at', ascending: false).limit(limit);
    final myId = _uid;
    final messages = (rows as List)
        .map((e) => _messageFromRow(Map<String, dynamic>.from(e as Map), myId))
        .toList()
        .reversed
        .toList();

    await _attachSenderNames(messages);
    await _attachReplyPreviews(messages);
    await _signAttachmentUrls(messages);
    return messages;
  }

  static Future<void> _attachReplyPreviews(List<ChatMessage> messages) async {
    final byId = {for (final m in messages) m.id: m};
    final missingReplyIds = <String>{};
    for (final m in messages) {
      if (m.replyToId != null && !byId.containsKey(m.replyToId)) {
        missingReplyIds.add(m.replyToId!);
      }
    }

    if (missingReplyIds.isNotEmpty) {
      final rows = await _client
          .from('chat_messages')
          .select(
            'id, room_id, sender_id, body, message_type, created_at, is_edited, deleted_at, '
            'moderation_state, reply_to_id, chat_message_attachments(id, storage_path, mime_type, file_name)',
          )
          .inFilter('id', missingReplyIds.toList());
      for (final raw in rows as List) {
        final reply = ChatMessage.fromJson(Map<String, dynamic>.from(raw as Map));
        byId[reply.id] = reply;
      }
      final extras = missingReplyIds.map((id) => byId[id]).whereType<ChatMessage>().toList();
      await _attachSenderNames(extras);
      await _signAttachmentUrls(extras);
    }

    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (m.replyToId != null && byId.containsKey(m.replyToId)) {
        messages[i] = m.copyWith(replyTo: byId[m.replyToId]);
      }
    }
  }

  static ChatMessage _messageFromRow(Map<String, dynamic> json, String myId) {
    final msg = ChatMessage.fromJson(json);
    return msg.copyWith(
      reactions: ChatReactionGroup.fromRows(json['chat_message_reactions'] as List?, myId),
    );
  }

  static Future<bool> toggleReaction(String messageId, String emoji) async {
    final added = await _client.rpc<bool>(
      'chat_toggle_reaction',
      params: {'p_message_id': messageId, 'p_emoji': emoji},
    );
    return added;
  }

  static const quickReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏', '🔥', '✅'];

  static Future<ChatMessage> hydrateMessage(ChatMessage message) async {
    var msg = message;
    if (msg.attachments.isEmpty &&
        (msg.messageType == ChatMessageType.image ||
            msg.messageType == ChatMessageType.video ||
            msg.messageType == ChatMessageType.file)) {
      final row = await _client
          .from('chat_messages')
          .select(
            'id, room_id, sender_id, body, message_type, created_at, is_edited, deleted_at, '
            'moderation_state, reply_to_id, chat_message_attachments(id, storage_path, mime_type, file_name, byte_size, width, height, duration_ms)',
          )
          .eq('id', msg.id)
          .maybeSingle();
      if (row != null) {
        msg = ChatMessage.fromJson(Map<String, dynamic>.from(row));
      }
    }

    await _attachSenderNames([msg]);
    if (msg.replyToId != null) {
      await _attachReplyPreviews([msg]);
    }
    await _signAttachmentUrls([msg]);
    return msg;
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
          String? url;
          if (CompanyFileStorage.isDropboxReference(a.storagePath)) {
            url = await CompanyFileStorage.resolveDisplayUrl(a.storagePath);
          } else {
            try {
              url = await _client.storage.from(_mediaBucket).createSignedUrl(a.storagePath, 3600);
            } catch (_) {
              url = await StorageFileAccess.resolveViewUrl(a.storagePath);
            }
          }
          signed.add(a.copyWith(signedUrl: url));
        } catch (_) {
          signed.add(a);
        }
      }
      messages[i] = m.copyWith(attachments: signed);
    }
  }

  static bool attachmentIsImage(ChatAttachment att, ChatMessageType type) =>
      att.isImage || type == ChatMessageType.image || _looksLikeImage(att);

  static bool attachmentIsVideo(ChatAttachment att, ChatMessageType type) =>
      att.isVideo || type == ChatMessageType.video || _looksLikeVideo(att);

  static bool _looksLikeImage(ChatAttachment att) {
    final name = (att.fileName ?? att.storagePath).toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp') ||
        name.endsWith('.gif') ||
        name.endsWith('.heic');
  }

  static bool _looksLikeVideo(ChatAttachment att) {
    final name = (att.fileName ?? att.storagePath).toLowerCase();
    return name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.webm') ||
        name.endsWith('.m4v');
  }

  static Future<String> sendMessage({
    required String roomId,
    required String body,
    String? replyToId,
    ChatMessageType messageType = ChatMessageType.text,
    Map<String, dynamic>? attachment,
    List<String>? mentionIds,
    String? threadRootId,
    int? expiresHours,
    String? translatedBody,
  }) async {
    return await _client.rpc<String>(
      'send_chat_message',
      params: {
        'p_room_id': roomId,
        'p_body': body.trim(),
        'p_reply_to_id': replyToId,
        'p_message_type': messageType.dbValue,
        'p_attachment': attachment,
        'p_mention_ids': mentionIds,
        'p_thread_root_id': threadRootId,
        'p_expires_hours': expiresHours,
        'p_translated_body': translatedBody,
      },
    );
  }

  static Future<Map<String, dynamic>?> fetchRoomMeta(String roomId) async {
    final row = await _client
        .from('chat_rooms')
        .select('welcome_message, rules_text, require_member_approval, pinned_message_id, parent_room_id')
        .eq('id', roomId)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  static Future<ChatMessage?> fetchPinnedMessage(String? messageId) async {
    if (messageId == null) return null;
    final rows = await fetchMessagesByIds([messageId]);
    return rows.isEmpty ? null : rows.first;
  }

  static Future<List<ChatMessage>> fetchMessagesByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _client
        .from('chat_messages')
        .select(
          'id, room_id, sender_id, body, message_type, created_at, is_edited, deleted_at, '
          'moderation_state, reply_to_id, expires_at, translated_body, thread_root_id, '
          'chat_message_attachments(id, storage_path, mime_type, file_name, byte_size, width, height, duration_ms)',
        )
        .inFilter('id', ids);
    final myId = _uid;
    final messages = (rows as List)
        .map((e) => _messageFromRow(Map<String, dynamic>.from(e as Map), myId))
        .toList();
    await _attachSenderNames(messages);
    await _signAttachmentUrls(messages);
    return messages;
  }

  static Future<List<ChatMessage>> fetchThread(String threadRootId) async {
    final rows = await _client
        .from('chat_messages')
        .select(
          'id, room_id, sender_id, body, message_type, created_at, is_edited, deleted_at, '
          'moderation_state, reply_to_id, expires_at, translated_body, thread_root_id, '
          'chat_message_attachments(id, storage_path, mime_type, file_name, byte_size, width, height, duration_ms), '
          'chat_message_reactions(emoji, user_id, profiles(full_name))',
        )
        .or('id.eq.$threadRootId,thread_root_id.eq.$threadRootId')
        .order('created_at');
    final myId = _uid;
    final messages = (rows as List)
        .map((e) => _messageFromRow(Map<String, dynamic>.from(e as Map), myId))
        .toList();
    await _attachSenderNames(messages);
    await _attachReplyPreviews(messages);
    await _signAttachmentUrls(messages);
    return messages;
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
    final path = 'chat/$roomId/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';

    final stored = await CompanyFileStorage.upload(
      supabaseBucket: _mediaBucket,
      storagePath: path,
      bytes: Uint8List.fromList(media.bytes),
      category: 'chat',
      fileName: media.fileName,
    );

    final storageRef = CompanyFileStorage.toStorageReference(stored);

    return sendMessage(
      roomId: roomId,
      body: caption,
      replyToId: replyToId,
      messageType: media.isVideo ? ChatMessageType.video : ChatMessageType.image,
      attachment: {
        'storage_path': storageRef,
        'mime_type': media.mimeType,
        'file_name': media.fileName,
        'byte_size': media.bytes.length,
        'storage_provider': stored.provider,
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

  static Future<void> moderatorDeleteMessage(String messageId) async {
    await _client.rpc('chat_moderator_delete_message', params: {'p_message_id': messageId});
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

  static Future<List<ChatRoomMember>> fetchRoomMembers(String roomId) async {
    final rows = await _client.rpc<dynamic>(
      'chat_room_members_list',
      params: {'p_room_id': roomId},
    );
    if (rows is! List) return const [];
    return rows
        .map((e) => ChatRoomMember.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<void> superadminRemoveFromRoom({
    required String roomId,
    required String userId,
  }) async {
    await _client.rpc('chat_superadmin_remove_from_room', params: {
      'p_room_id': roomId,
      'p_user_id': userId,
    });
  }

  static Future<void> superadminDeleteRoom(String roomId) async {
    await _client.rpc('chat_superadmin_delete_room', params: {
      'p_room_id': roomId,
    });
  }

  static Future<void> leaveRoom(String roomId) async {
    await _client.rpc('chat_leave_room', params: {'p_room_id': roomId});
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
          callback: (payload) async {
            try {
              final record = payload.newRecord;
              if (record.isEmpty) return;
              final msgRoomId = record['room_id'] as String?;
              if (msgRoomId != roomId) return;
              var msg = ChatMessage.fromJson(Map<String, dynamic>.from(record));
              msg = await hydrateMessage(msg);
              onMessage(msg);
            } catch (_) {
              // Realtime payload kan mangle joins — ignorer, fallback henter via roomInserts.
            }
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
