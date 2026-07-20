import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../../models/vision_camera.dart';
import '../supabase_service.dart';

class VisionScanStatus {
  const VisionScanStatus({
    required this.active,
    required this.persons,
    required this.violationsSession,
  });

  final bool active;
  final int persons;
  final int violationsSession;
}

/// Live feed-linje fra vision worker (grønn = ok, rød = avvik).
class VisionFeedLine {
  const VisionFeedLine({
    required this.id,
    required this.text,
    required this.status,
    this.trackId,
  });

  final String id;
  final String text;
  final String status;
  final int? trackId;

  bool get isOk => status == 'ok';
  bool get isViolation => status == 'violation';
  bool get isScan => status == 'scan';
}

class LiveFrameResult {
  const LiveFrameResult({this.bytes, this.error, this.source});

  final Uint8List? bytes;
  final String? error;
  /// `edge`, `local_worker`, eller null.
  final String? source;

  bool get ok => bytes != null && bytes!.isNotEmpty;
}

class VisionCameraService {
  VisionCameraService._();

  static final VisionCameraService instance = VisionCameraService._();

  static SupabaseClient get _client => SupabaseService.client;

  Future<String?> _companyId() => SupabaseService.getCurrentCompanyId();

  Future<List<VisionCamera>> fetchCameras() async {
    final rows = await _client.rpc('list_vision_cameras_masked') as List<dynamic>;
    return rows
        .map((r) => VisionCamera.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<VisionCamera> upsertCamera({
    String? id,
    required String name,
    required String host,
    int httpPort = 80,
    String cameraUser = 'admin',
    String? cameraPassword,
    String snapshotPath = '/ISAPI/Streaming/channels/101/picture',
    String eventType = 'uniform_violation',
    bool enabled = true,
  }) async {
    final cid = await _companyId();
    if (cid == null) throw StateError('Ingen bedrift');

    final payload = {
      'company_id': cid,
      'name': name.trim(),
      'host': host.trim(),
      'http_port': httpPort,
      'camera_user': cameraUser.trim(),
      'snapshot_path': snapshotPath.trim(),
      'event_type': eventType,
      'enabled': enabled,
      'updated_at': DateTime.now().toIso8601String(),
      if (cameraPassword != null && cameraPassword.isNotEmpty)
        'camera_password': cameraPassword,
    };

    if (id != null) {
      await _client.from('vision_cameras').update(payload).eq('id', id);
      final list = await fetchCameras();
      return list.firstWhere((c) => c.id == id);
    }

    final row = await _client
        .from('vision_cameras')
        .insert(payload)
        .select('id')
        .single();
    final newId = row['id'] as String;
    final list = await fetchCameras();
    return list.firstWhere((c) => c.id == newId);
  }

  Future<void> deleteCamera(String id) async {
    await _client.from('vision_cameras').delete().eq('id', id);
  }

  Future<List<VisionEvent>> fetchRecentEvents({int limit = 100}) async {
    final cid = await _companyId();
    if (cid == null) return [];

    final rows = await _client
        .from('vision_events')
        .select()
        .eq('company_id', cid)
        .order('occurred_at', ascending: false)
        .limit(limit) as List<dynamic>;

    return rows
        .map((r) => VisionEvent.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<VisionEvent>> fetchUniformViolations({int limit = 80}) async {
    final events = await fetchRecentEvents(limit: limit);
    return events
        .where((e) => e.eventType == 'uniform_violation' || e.eventType == 'ppe_violation')
        .toList();
  }

  Future<List<VisionCamera>> fetchUniformCameras() async {
    final cameras = await fetchCameras();
    return cameras
        .where((c) => c.enabled && c.eventType == 'uniform_violation')
        .toList();
  }

  static const String localWorkerScanUrl = 'http://localhost:8090/api/scan';
  static const String localWorkerEventsUrl = 'http://localhost:8090/api/events';
  static const String localWorkerEventsClearUrl =
      'http://localhost:8090/api/events/clear';
  static const String localWorkerFeedUrl = 'http://localhost:8090/api/feed';

  /// Brudd/hendelser for uniform-monitor — lokal worker i dev, Supabase i prod (iOS/Android).
  Future<List<VisionEvent>> fetchMonitorViolations() async {
    if (kDebugMode) {
      final local = await fetchLocalViolations();
      if (local.isNotEmpty) return local;
    }
    return fetchUniformViolations();
  }

  /// Skannestatus — kun tilgjengelig mot lokal worker (utvikling).
  Future<VisionScanStatus?> fetchMonitorScanStatus() async {
    if (kDebugMode) return fetchLocalScanStatus();
    return null;
  }

  Future<List<VisionFeedLine>> fetchMonitorScanFeed() async {
    if (kDebugMode) return fetchLocalScanFeed();
    return [];
  }

  /// Nullstiller lokale brudd i worker (kun dev).
  Future<bool> clearLocalViolations() async {
    if (!kDebugMode && !kIsWeb) return false;
    try {
      final res = await http.get(Uri.parse(localWorkerEventsClearUrl));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<VisionEvent>> fetchLocalViolations() async {
    if (!kDebugMode && !kIsWeb) return [];
    try {
      final res = await http.get(Uri.parse(localWorkerEventsUrl));
      if (res.statusCode != 200) return [];
      final decoded = jsonDecode(res.body);
      if (decoded is! List) return [];
      final out = <VisionEvent>[];
      for (final raw in decoded) {
        if (raw is! Map) continue;
        try {
          final row = Map<String, dynamic>.from(raw);
          final imagePath = row['image_url'] as String? ?? '';
          final imageUrl = imagePath.startsWith('http')
              ? imagePath
              : 'http://localhost:8090$imagePath';
          final metaRaw = row['metadata'];
          final metadata = metaRaw is Map
              ? Map<String, dynamic>.from(metaRaw)
              : <String, dynamic>{};
          out.add(
            VisionEvent(
              id: row['id']?.toString() ?? '',
              cameraId: row['camera_id']?.toString() ?? '',
              eventType: row['event_type'] as String? ?? 'uniform_violation',
              status: row['status'] as String? ?? 'open',
              dropboxImageUrl: imageUrl,
              occurredAt: DateTime.tryParse(row['timestamp']?.toString() ?? '') ??
                  DateTime.now(),
              metadata: metadata,
            ),
          );
        } catch (_) {
          continue;
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<VisionScanStatus?> fetchLocalScanStatus() async {
    if (!kDebugMode && !kIsWeb) return null;
    try {
      final res = await http.get(Uri.parse(localWorkerScanUrl));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return VisionScanStatus(
        active: data['active'] == true,
        persons: (data['persons'] as num?)?.toInt() ?? 0,
        violationsSession: (data['violations_session'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<VisionFeedLine>> fetchLocalScanFeed() async {
    if (!kDebugMode && !kIsWeb) return [];
    try {
      final res = await http.get(Uri.parse(localWorkerFeedUrl));
      if (res.statusCode != 200) return [];
      final rows = jsonDecode(res.body) as List<dynamic>;
      return rows.map((raw) {
        final row = Map<String, dynamic>.from(raw as Map);
        return VisionFeedLine(
          id: row['id'] as String? ?? '',
          text: row['text'] as String? ?? '',
          status: row['status'] as String? ?? 'scan',
          trackId: (row['track_id'] as num?)?.toInt(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Henter live JPEG — Supabase edge, med lokal worker-fallback i debug.
  static const String localWorkerLiveUrl = 'http://localhost:8090/live.jpg';

  Future<LiveFrameResult> fetchLiveFrame(String cameraId) async {
    // Lokal utvikling: hopp over edge (ikke deployet) og bruk worker direkte.
    if (kDebugMode) {
      final local = await _fetchLocalWorkerFallback(null);
      if (local.ok) return local;
    }

    final session = _client.auth.currentSession;
    if (session == null) {
      return const LiveFrameResult(error: 'Ikke innlogget');
    }

    final uri = Uri.parse(
      '${SupabaseConfig.url}/functions/v1/vision-camera?action=snapshot&camera_id=$cameraId',
    );
    try {
      final res = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': SupabaseConfig.anonKey,
        },
      );
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        return LiveFrameResult(bytes: res.bodyBytes, source: 'edge');
      }
      if (res.statusCode == 404) {
        return _fetchLocalWorkerFallback(null);
      }
      if (kDebugMode) {
        return _fetchLocalWorkerFallback(null);
      }
      return const LiveFrameResult(error: 'Kobler til kamera…');
    } catch (e) {
      if (kDebugMode) {
        return _fetchLocalWorkerFallback(null);
      }
      return const LiveFrameResult(error: 'Kobler til kamera…');
    }
  }

  Future<LiveFrameResult> _fetchLocalWorkerFallback(String? hint) async {
    try {
      final res = await http.get(
        Uri.parse('$localWorkerLiveUrl?${DateTime.now().millisecondsSinceEpoch}'),
      );
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        return LiveFrameResult(bytes: res.bodyBytes, source: 'local_worker');
      }
      final prefix = hint != null ? '$hint\n\n' : '';
      return LiveFrameResult(
        error: '${prefix}Kunne ikke koble til lokal kamera-worker.',
      );
    } catch (e) {
      final prefix = hint != null ? '$hint\n\n' : '';
      return LiveFrameResult(
        error: '${prefix}Kunne ikke koble til lokal kamera-worker.',
      );
    }
  }
}
