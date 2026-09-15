import 'dart:html' as html;

class AssistantFabPrefsImpl {
  static String _key(String userId) => 'driftpro.assistant.fab.enabled.$userId';

  static Future<bool> loadEnabled(String userId) async {
    final raw = html.window.localStorage[_key(userId)];
    if (raw == null) return true;
    return raw != '0' && raw.toLowerCase() != 'false';
  }

  static Future<void> saveEnabled(String userId, bool enabled) async {
    html.window.localStorage[_key(userId)] = enabled ? '1' : '0';
  }
}
