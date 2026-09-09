import 'dart:html' as html;

/// Lagrer Spør DriftPro-ikonets posisjon per bruker i browser localStorage.
class AssistantFabPositionStore {
  AssistantFabPositionStore._();

  static String _key(String userId) => 'driftpro.assistant.fab.pos.$userId';

  static ({double left, double top})? load(String userId) {
    if (userId.isEmpty) return null;
    try {
      final raw = html.window.localStorage[_key(userId)];
      if (raw == null || raw.isEmpty) return null;
      final parts = raw.split(',');
      if (parts.length != 2) return null;
      final left = double.tryParse(parts[0]);
      final top = double.tryParse(parts[1]);
      if (left == null || top == null) return null;
      if (!left.isFinite || !top.isFinite) return null;
      return (left: left, top: top);
    } catch (_) {
      return null;
    }
  }

  static Future<({double left, double top})?> loadAsync(String userId) async =>
      load(userId);

  static void save(String userId, {required double left, required double top}) {
    if (userId.isEmpty) return;
    try {
      html.window.localStorage[_key(userId)] =
          '${left.toStringAsFixed(1)},${top.toStringAsFixed(1)}';
    } catch (_) {}
  }
}
