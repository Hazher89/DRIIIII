import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'hms_ecosystem_service.dart';
import '../supabase_service.dart';

/// Offline-first kø for HMS-registreringer — synker mot Supabase når nett er tilbake.
class HmsOfflineSyncService {
  HmsOfflineSyncService._();

  static const _boxName = 'hms_offline_queue_v1';
  static Box<String>? _box;

  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox<String>(_boxName);
  }

  static Future<String> queueTicketDraft({
    required Map<String, dynamic> payload,
  }) async {
    final clientId = const Uuid().v4();
    final entry = jsonEncode({
      'entity_type': 'ticket',
      'client_id': clientId,
      'operation': 'insert',
      'payload': payload,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _box?.put(clientId, entry);

    try {
      await HmsEcosystemService.enqueueOfflineSync(
        entityType: 'ticket',
        clientId: clientId,
        operation: 'insert',
        payload: payload,
      );
    } catch (_) {}

    return clientId;
  }

  static Future<int> syncPending() async {
    if (!SupabaseService.isConfigured) return 0;
    if (_box == null) await init();

    var synced = 0;
    final keys = _box!.keys.toList();
    for (final key in keys) {
      final raw = _box!.get(key);
      if (raw == null) continue;

      final map = jsonDecode(raw) as Map<String, dynamic>;
      final type = map['entity_type'] as String;
      final payload = map['payload'] as Map<String, dynamic>;

      try {
        if (type == 'ticket') {
          await Supabase.instance.client.from('tickets').insert({
            ...payload,
            'offline_client_id': map['client_id'],
            'synced_at': DateTime.now().toIso8601String(),
          });
        }
        await _box!.delete(key);
        synced++;
      } catch (_) {
        // Behold i kø til neste forsøk
      }
    }
    return synced;
  }

  static int get pendingCount => _box?.length ?? 0;
}
