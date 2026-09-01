import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_service.dart';
import 'chat_pending_navigation.dart';
import 'chat_presence_service.dart';
import 'chat_unread_service.dart';
import 'chat_web_notifications.dart';

/// Varsler ved nye chat-meldinger — særlig nettleser på web.
abstract final class ChatRealtimeNotificationService {
  static RealtimeChannel? _channel;
  static bool _webPermissionAsked = false;

  static Future<void> start() async {
    if (SupabaseService.currentUser?.id == null) return;
    stop();

    if (kIsWeb) {
      await _ensureWebPermissionPrompt();
    }

    _channel = SupabaseService.client
        .channel('chat_global_notify')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          callback: (payload) => unawaited(_onNewMessage(payload.newRecord)),
        )
        ..subscribe();
  }

  static void stop() {
    if (_channel != null) {
      SupabaseService.client.removeChannel(_channel!);
      _channel = null;
    }
  }

  static Future<void> _ensureWebPermissionPrompt() async {
    if (_webPermissionAsked) return;
    _webPermissionAsked = true;
    if (!await chatWebNotificationsSupported()) return;
    if (await chatWebNotificationsGranted()) return;
    // Bruker aktiverer via banner i hub — ikke auto-popup ved første load.
  }

  static Future<bool> enableWebNotifications() async {
    if (!kIsWeb) return false;
    return requestChatWebNotificationPermission();
  }

  static Future<bool> webNotificationsEnabled() async {
    if (!kIsWeb) return false;
    return chatWebNotificationsGranted();
  }

  static Future<void> _onNewMessage(Map<String, dynamic> record) async {
    final uid = SupabaseService.currentUser?.id;
    if (uid == null || record.isEmpty) return;

    final senderId = record['sender_id'] as String?;
    if (senderId == uid) return;

    final roomId = record['room_id'] as String?;
    if (roomId == null) return;

    if (ChatPresenceService.openRoomId == roomId && !chatWebPageIsHidden()) {
      return;
    }

    unawaited(ChatUnreadService.refresh());

    if (!kIsWeb || !await chatWebNotificationsGranted()) return;

    final body = (record['body'] as String?)?.trim();
    final preview = body != null && body.isNotEmpty
        ? body
        : switch (record['message_type'] as String?) {
            'image' => '📷 Bilde',
            'video' => '🎬 Video',
            _ => 'Ny melding',
          };

    var title = 'Ny melding';
    try {
      final room = await SupabaseService.client
          .from('chat_rooms')
          .select('title, room_type')
          .eq('id', roomId)
          .maybeSingle();
      if (room != null) {
        final t = (room['title'] as String?)?.trim();
        if (t != null && t.isNotEmpty) {
          title = t;
        } else {
          title = switch (room['room_type'] as String?) {
            'partner_broadcast' => 'Meldinger fra MAVI',
            'partner_private' => 'Privat chat',
            'partner_group' => 'Partner-gruppe',
            'mavi_group' => 'MAVI-gruppe',
            _ => 'Ny melding',
          };
        }
      }
    } catch (_) {}

    showChatWebNotification(
      title: title,
      body: preview.length > 120 ? '${preview.substring(0, 120)}…' : preview,
      roomId: roomId,
      onTap: (id) => ChatPendingNavigation.setRoom(id),
    );
  }
}
