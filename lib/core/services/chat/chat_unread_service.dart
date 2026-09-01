import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_service.dart';
import 'partner_chat_service.dart';

/// Totalt antall uleste chat-meldinger — for dock-badge.
abstract final class ChatUnreadService {
  static SupabaseClient get _client => SupabaseService.client;
  static final _controller = StreamController<int>.broadcast();
  static final _roomInsertController = StreamController<String>.broadcast();
  static int _lastCount = 0;
  static RealtimeChannel? _channel;
  static Timer? _debounce;
  static String? _watchingUserId;

  static Stream<int> get stream => _controller.stream;
  /// Nye meldinger per rom-id (ufiltrert realtime — brukes som fallback i aktiv chat).
  static Stream<String> get roomInserts => _roomInsertController.stream;
  static int get lastCount => _lastCount;

  static void startWatching() {
    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return;

    if (_watchingUserId != uid) {
      stopWatching();
      _watchingUserId = uid;
      _lastCount = -1;
    }

    unawaited(refresh());

    if (_channel != null) return;

    _channel = _client
        .channel('chat_unread_badge_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          callback: (payload) {
            final roomId = payload.newRecord['room_id'] as String?;
            if (roomId != null && !_roomInsertController.isClosed) {
              _roomInsertController.add(roomId);
            }
            _scheduleRefresh();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_rooms',
          callback: (_) => _scheduleRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_read_state',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => _scheduleRefresh(),
        )
        ..subscribe();
  }

  static void stopWatching() {
    _debounce?.cancel();
    _watchingUserId = null;
    if (_channel != null) {
      _client.removeChannel(_channel!);
      _channel = null;
    }
  }

  static void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(refresh());
    });
  }

  static Future<void> refresh() async {
    if (SupabaseService.currentUser?.id == null) {
      _emit(0);
      return;
    }
    try {
      final count = await PartnerChatService.fetchTotalUnread();
      _emit(count);
    } catch (_) {}
  }

  static void _emit(int count) {
    if (count == _lastCount) return;
    _lastCount = count;
    if (!_controller.isClosed) _controller.add(count);
  }
}
