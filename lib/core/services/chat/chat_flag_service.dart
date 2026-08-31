import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_service.dart';

/// Remote flagg for partner ↔ MAVI chat (live via Realtime).
class ChatFlag {
  const ChatFlag({
    required this.maviEnabled,
    required this.partnersEnabled,
  });

  final bool maviEnabled;
  final bool partnersEnabled;

  static const allEnabled = ChatFlag(maviEnabled: true, partnersEnabled: true);

  bool get enabledForMavi => maviEnabled;
  bool get enabledForPartners => partnersEnabled;

  factory ChatFlag.fromRow(Map<String, dynamic>? row) {
    if (row == null) return ChatFlag.allEnabled;
    return ChatFlag(
      maviEnabled: row['chat_enabled_mavi'] != false,
      partnersEnabled: row['chat_enabled_partners'] != false,
    );
  }

  factory ChatFlag.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ChatFlag.allEnabled;
    return ChatFlag(
      maviEnabled: json['chat_enabled_mavi'] != false,
      partnersEnabled: json['chat_enabled_partners'] != false,
    );
  }
}

abstract final class ChatFlagService {
  static SupabaseClient get _client => SupabaseService.client;

  static Future<ChatFlag> fetchForCompany(String companyId) async {
    try {
      final row = await _client
          .from('companies')
          .select('chat_enabled_mavi, chat_enabled_partners')
          .eq('id', companyId)
          .maybeSingle();
      return ChatFlag.fromRow(row == null ? null : Map<String, dynamic>.from(row));
    } catch (_) {
      return ChatFlag.allEnabled;
    }
  }

  /// Realtime + lett poll — app/web oppdateres uten rebuild.
  static Stream<ChatFlag> watch(String companyId) {
    late StreamController<ChatFlag> controller;
    RealtimeChannel? channel;
    Timer? poll;
    var closed = false;

    controller = StreamController<ChatFlag>(
      onListen: () async {
        final initial = await fetchForCompany(companyId);
        if (!closed) controller.add(initial);

        channel = _client
            .channel('chat-flag-$companyId')
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'companies',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'id',
                value: companyId,
              ),
              callback: (payload) {
                controller.add(ChatFlag.fromRow(payload.newRecord));
              },
            )
            .subscribe();

        // Fallback hvis Realtime-abonnement mangler / er tregt.
        poll = Timer.periodic(const Duration(seconds: 20), (_) async {
          if (closed) return;
          final next = await fetchForCompany(companyId);
          if (!closed) controller.add(next);
        });
      },
      onCancel: () async {
        closed = true;
        poll?.cancel();
        if (channel != null) {
          await _client.removeChannel(channel!);
        }
      },
    );

    return controller.stream;
  }

  static Future<ChatFlag> setFlags({
    required bool maviEnabled,
    required bool partnersEnabled,
  }) async {
    final data = await _client.rpc<Map<String, dynamic>>(
      'set_company_chat_enabled',
      params: {
        'p_mavi': maviEnabled,
        'p_partners': partnersEnabled,
      },
    );
    return ChatFlag(
      maviEnabled: data['chat_enabled_mavi'] != false,
      partnersEnabled: data['chat_enabled_partners'] != false,
    );
  }
}
