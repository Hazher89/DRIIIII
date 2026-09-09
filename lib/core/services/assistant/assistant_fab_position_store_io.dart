import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Lagrer Spør DriftPro-ikonets posisjon per bruker (iOS/Android/desktop).
class AssistantFabPositionStore {
  AssistantFabPositionStore._();

  static final Map<String, ({double left, double top})> _memory = {};

  static String _fileName(String userId) =>
      'driftpro_assistant_fab_pos_${userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.json';

  static Future<File> _file(String userId) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/${_fileName(userId)}');
  }

  static ({double left, double top})? load(String userId) {
    if (userId.isEmpty) return null;
    final cached = _memory[userId];
    if (cached != null) return cached;
    // Sync API for overlay — kick off async hydrate.
    _hydrate(userId);
    return null;
  }

  static Future<void> _hydrate(String userId) async {
    try {
      final f = await _file(userId);
      if (!await f.exists()) return;
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final left = (map['left'] as num?)?.toDouble();
      final top = (map['top'] as num?)?.toDouble();
      if (left == null || top == null) return;
      _memory[userId] = (left: left, top: top);
    } catch (_) {}
  }

  static void save(String userId, {required double left, required double top}) {
    if (userId.isEmpty) return;
    _memory[userId] = (left: left, top: top);
    unawaitedSave(userId, left: left, top: top);
  }

  static void unawaitedSave(
    String userId, {
    required double left,
    required double top,
  }) {
    () async {
      try {
        final f = await _file(userId);
        await f.parent.create(recursive: true);
        await f.writeAsString(jsonEncode({'left': left, 'top': top}));
      } catch (_) {}
    }();
  }

  /// Call once after login so disk position is ready before first paint.
  static Future<({double left, double top})?> loadAsync(String userId) async {
    if (userId.isEmpty) return null;
    await _hydrate(userId);
    return _memory[userId];
  }
}
