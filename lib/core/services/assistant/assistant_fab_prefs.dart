import 'assistant_fab_prefs_stub.dart'
    if (dart.library.html) 'assistant_fab_prefs_web.dart'
    if (dart.library.io) 'assistant_fab_prefs_io.dart';

/// Per-bruker: synlig flyttbar chat-boble (kun relevant for MAVI-ansatte).
class AssistantFabPrefs {
  static Future<bool> isEnabled(String userId) =>
      AssistantFabPrefsImpl.loadEnabled(userId);

  static Future<void> setEnabled(String userId, bool enabled) =>
      AssistantFabPrefsImpl.saveEnabled(userId, enabled);
}
