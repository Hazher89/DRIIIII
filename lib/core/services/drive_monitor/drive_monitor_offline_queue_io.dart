import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Lokal kø for leiebil-sporing — overlever nettbrudd og app-restart.
class DriveMonitorOfflineQueue {
  DriveMonitorOfflineQueue(this.sessionId);

  final String sessionId;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    final folder = Directory('${dir.path}/drive_monitor_queue');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return File('${folder.path}/$sessionId.json');
  }

  Future<Map<String, dynamic>> _read() async {
    try {
      final f = await _file();
      if (!await f.exists()) {
        return {'samples': <dynamic>[], 'events': <dynamic>[]};
      }
      final raw = jsonDecode(await f.readAsString());
      if (raw is Map<String, dynamic>) return raw;
    } catch (_) {}
    return {'samples': <dynamic>[], 'events': <dynamic>[]};
  }

  Future<void> _write(Map<String, dynamic> data) async {
    final f = await _file();
    await f.writeAsString(jsonEncode(data));
  }

  Future<void> enqueueSamples(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final data = await _read();
    final list = List<dynamic>.from(data['samples'] as List? ?? const []);
    list.addAll(rows);
    if (list.length > 12000) {
      list.removeRange(0, list.length - 12000);
    }
    data['samples'] = list;
    await _write(data);
  }

  Future<void> enqueueEvents(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final data = await _read();
    final list = List<dynamic>.from(data['events'] as List? ?? const []);
    list.addAll(rows);
    if (list.length > 4000) {
      list.removeRange(0, list.length - 4000);
    }
    data['events'] = list;
    await _write(data);
  }

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> peek() async {
    final data = await _read();
    final samples = (data['samples'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final events = (data['events'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return (samples, events);
  }

  Future<void> replace({
    required List<Map<String, dynamic>> samples,
    required List<Map<String, dynamic>> events,
  }) async {
    await _write({
      'samples': samples,
      'events': events,
    });
  }

  Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
