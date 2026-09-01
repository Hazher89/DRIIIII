import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_service.dart';
import 'partner_chat_service.dart';

/// Totalt antall uleste chat-meldinger — for dock-badge.
abstract final class ChatUnreadService {
  static SupabaseClient get _client => SupabaseService.client;
  static final _controller = StreamController<int>.broadcast();
  static int _lastCount = 0;
  static RealtimeChannel? _channel;
  static Timer? _debounce;

  static Stream<int> get stream => _controller.stream;
  static int get lastCount => _lastCount;

  static void startWatching() {
    if (SupabaseService.currentUser?.id == null) return;
    unawaited(refresh());
    _channel ??= _client
        .channel('chat_unread_badge')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          callback: (_) => _scheduleRefresh(),
        )
        ..subscribe();
  }

  static void stopWatching() {
    _debounce?.cancel();
    if (_channel != null) {
      _client.removeChannel(_channel!);
      _channel = null;
    }
  }

  static void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
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
