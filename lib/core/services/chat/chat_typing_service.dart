import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_service.dart';

/// «Skriver…» via Realtime broadcast (ingen DB).
class ChatTypingService {
  ChatTypingService({
    required this.roomId,
    required this.userId,
    required this.userName,
  });

  final String roomId;
  final String userId;
  final String userName;

  static const _event = 'typing';
  static const _ttl = Duration(seconds: 4);

  final _othersCtrl = StreamController<Map<String, String>>.broadcast();
  RealtimeChannel? _channel;
  Timer? _debounce;
  bool _disposed = false;
  final Map<String, DateTime> _active = {};
  final Map<String, String> _names = {};

  Stream<Map<String, String>> get others => _othersCtrl.stream;

  void start() {
    _channel = SupabaseService.client
        .channel('chat_typing_$roomId')
        .onBroadcast(
          event: _event,
          callback: (payload) {
            final uid = payload['user_id'] as String?;
            final name = (payload['user_name'] as String?)?.trim();
            if (uid == null || uid == userId) return;
            if (name != null && name.isNotEmpty) _names[uid] = name;
            _active[uid] = DateTime.now();
            _emit();
            Timer(_ttl, () {
              final t = _active[uid];
              if (t != null && DateTime.now().difference(t) >= _ttl) {
                _active.remove(uid);
                _emit();
              }
            });
          },
        )
        ..subscribe();
  }

  void onUserTyping() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _broadcastTyping);
  }

  void _broadcastTyping() {
    _channel?.sendBroadcastMessage(
      event: _event,
      payload: {'user_id': userId, 'user_name': userName},
    );
  }

  void _emit() {
    if (_disposed || _othersCtrl.isClosed) return;
    final now = DateTime.now();
    _active.removeWhere((_, t) => now.difference(t) > _ttl);
    final map = <String, String>{};
    for (final e in _active.entries) {
      map[e.key] = _names[e.key] ?? 'Noen';
    }
    _othersCtrl.add(map);
  }

  static String typingLabel(Map<String, String> names) {
    final list = names.values.toList();
    if (list.isEmpty) return '';
    if (list.length == 1) return '${list.first} skriver…';
    if (list.length == 2) return '${list[0]} og ${list[1]} skriver…';
    return '${list.length} personer skriver…';
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    if (_channel != null) {
      SupabaseService.client.removeChannel(_channel!);
      _channel = null;
    }
    _othersCtrl.close();
  }
}
