import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_service.dart';

class AssistantFlag {
  const AssistantFlag({
    required this.enabled,
    this.title,
  });

  final bool enabled;
  final String? title;

  String get displayTitle {
    final t = title?.trim();
    if (t == null || t.isEmpty) return 'Spør DriftPro';
    return t;
  }

  static const disabled = AssistantFlag(enabled: false);
}

/// Remote av/på for kunnskaps-chatten (uten app-oppdatering).
class AssistantFlagService {
  AssistantFlagService._();

  static SupabaseClient get _client => SupabaseService.client;

  static Future<AssistantFlag> fetchForCompany(String companyId) async {
    try {
      final row = await _client
          .from('companies')
          .select('assistant_enabled, assistant_title')
          .eq('id', companyId)
          .maybeSingle();
      if (row == null) return AssistantFlag.disabled;
      return AssistantFlag(
        enabled: row['assistant_enabled'] == true,
        title: row['assistant_title'] as String?,
      );
    } catch (_) {
      return AssistantFlag.disabled;
    }
  }

  /// Realtime + initial fetch. Caller må cancel stream-subscription.
  static Stream<AssistantFlag> watch(String companyId) {
    late StreamController<AssistantFlag> controller;
    RealtimeChannel? channel;
    var closed = false;

    controller = StreamController<AssistantFlag>(
      onListen: () async {
        final initial = await fetchForCompany(companyId);
        if (!closed) controller.add(initial);

        channel = _client
            .channel('assistant-flag-$companyId')
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
                final row = payload.newRecord;
                controller.add(
                  AssistantFlag(
                    enabled: row['assistant_enabled'] == true,
                    title: row['assistant_title'] as String?,
                  ),
                );
              },
            )
            .subscribe();
      },
      onCancel: () async {
        closed = true;
        final ch = channel;
        channel = null;
        if (ch != null) {
          await _client.removeChannel(ch);
        }
      },
    );

    return controller.stream;
  }

  static Future<AssistantFlag> setEnabled({
    required bool enabled,
    String? title,
  }) async {
    final data = await _client.rpc(
      'set_company_assistant_enabled',
      params: {
        'p_enabled': enabled,
        'p_title': title,
      },
    );
    if (data is Map) {
      return AssistantFlag(
        enabled: data['assistant_enabled'] == true || enabled,
        title: data['assistant_title'] as String? ?? title,
      );
    }
    return AssistantFlag(enabled: enabled, title: title);
  }
}
