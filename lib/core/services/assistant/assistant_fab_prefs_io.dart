import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AssistantFabPrefsImpl {
  static Future<File> _file(String userId) async {
    final dir = await getApplicationSupportDirectory();
    final safe = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File('${dir.path}/driftpro_assistant_fab_enabled_$safe.json');
  }

  static Future<bool> loadEnabled(String userId) async {
    try {
      final f = await _file(userId);
      if (!await f.exists()) return true;
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return map['enabled'] != false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> saveEnabled(String userId, bool enabled) async {
    final f = await _file(userId);
    await f.writeAsString(jsonEncode({'enabled': enabled}));
  }
}
