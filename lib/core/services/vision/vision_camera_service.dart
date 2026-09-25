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

class VisionMediaLink {
  const VisionMediaLink({required this.url, required this.kind});

  final String url;
  /// `video` eller `image`.
  final String kind;

  bool get isVideo => kind == 'video';
  bool get isImage => kind == 'image';
}

class VisionLearnSession {
  const VisionLearnSession({
    required this.id,
    required this.companyId,
    required this.cameraId,
    required this.status,
    required this.startedAt,
    this.stoppedAt,
    this.dropboxVideoPath,
    this.dropboxVideoUrl,
    this.dropboxPaths = const [],
    this.durationSeconds,
    this.chunkCount = 0,
    this.errorMessage,
  });

  final String id;
  final String companyId;
  final String cameraId;
  final String status;
  final DateTime startedAt;
  final DateTime? stoppedAt;
  final String? dropboxVideoPath;
  final String? dropboxVideoUrl;
  final List<String> dropboxPaths;
  final double? durationSeconds;
  final int chunkCount;
  final String? errorMessage;

  bool get isRecording => status == 'recording' || status == 'uploading';
  bool get isReady => status == 'ready';

  factory VisionLearnSession.fromRow(Map<String, dynamic> row) {
    final pathsRaw = row['dropbox_paths'];
    final paths = <String>[];
    if (pathsRaw is List) {
      for (final p in pathsRaw) {
        if (p != null && p.toString().isNotEmpty) paths.add(p.toString());
      }
    }
    return VisionLearnSession(
      id: row['id'] as String,
      companyId: row['company_id'] as String,
      cameraId: row['camera_id'] as String,
      status: row['status'] as String? ?? 'recording',
      startedAt: DateTime.parse(row['started_at'] as String),
      stoppedAt: row['stopped_at'] != null
          ? DateTime.tryParse(row['stopped_at'].toString())
          : null,
      dropboxVideoPath: row['dropbox_video_path'] as String?,
      dropboxVideoUrl: row['dropbox_video_url'] as String?,
      dropboxPaths: paths,
      durationSeconds: (row['duration_seconds'] as num?)?.toDouble(),
      chunkCount: (row['chunk_count'] as num?)?.toInt() ?? 0,
      errorMessage: row['error_message'] as String?,
    );
  }
}

class VisionLearnLabel {
  const VisionLearnLabel({
    required this.id,
    required this.sessionId,
    required this.label,
    this.zone,
    this.reason,
    this.note,
    this.timestampInVideoSec,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final String label;
  final String? zone;
  final String? reason;
  final String? note;
  final double? timestampInVideoSec;
  final DateTime createdAt;

  factory VisionLearnLabel.fromRow(Map<String, dynamic> row) {
    return VisionLearnLabel(
      id: row['id'] as String,
      sessionId: row['session_id'] as String,
      label: row['label'] as String,
      zone: row['zone'] as String?,
      reason: row['reason'] as String?,
      note: row['note'] as String?,
      timestampInVideoSec:
          (row['timestamp_in_video_sec'] as num?)?.toDouble(),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
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
      // Behold eksisterende company_id — lagring under Demo har tidligere
      // flyttet MAVI-kamera og skjult sorting-klipp i DriftPro.
      await _client.from('vision_cameras').update(payload).eq('id', id);
      final list = await fetchCameras();
      return list.firstWhere((c) => c.id == id);
    }

    final row = await _client
        .from('vision_cameras')
        .insert({
          ...payload,
          'company_id': cid,
        })
        .select('id')
        .single();
    final newId = row['id'] as String;
    final list = await fetchCameras();
    return list.firstWhere((c) => c.id == newId);
  }

  Future<void> deleteCamera(String id) async {
    await _client.from('vision_cameras').delete().eq('id', id);
  }

  Future<List<VisionEvent>> fetchRecentEvents({
    int limit = 100,
    bool includeArchived = false,
    bool includeDismissed = false,
    String? companyIdOverride,
  }) async {
    final cid = companyIdOverride ?? await _companyId();
    if (cid == null) return [];

    var query = _client
        .from('vision_events')
        .select()
        .eq('company_id', cid)
        .order('occurred_at', ascending: false)
        .limit(limit);

    final rows = await query as List<dynamic>;

    return rows
        .map((r) => VisionEvent.fromRow(Map<String, dynamic>.from(r as Map)))
        .where((e) {
          if (!includeDismissed && e.isDismissed) return false;
          if (!includeArchived && e.isArchived) return false;
          return true;
        })
        .toList();
  }

  Future<List<VisionEvent>> fetchUniformViolations({int limit = 80}) async {
    final events = await fetchRecentEvents(limit: limit);
    return events
        .where((e) =>
            e.eventType == 'uniform_violation' || e.eventType == 'ppe_violation')
        .toList();
  }

  Future<List<VisionEvent>> fetchSortingEvents({
    int limit = 80,
    bool includeArchived = false,
  }) async {
    if (kDebugMode) {
      final local = await fetchLocalViolations();
      final sortingLocal =
          local.where((e) => e.eventType == 'sorting_clip').toList();
      if (sortingLocal.isNotEmpty) return sortingLocal;
    }

    // Superadmin kan ha Demo som profil-company (Dropbox), mens sorteringsklipp
    // ligger på MAVI (00000000). Hent begge når nødvendig.
    const maviCompanyId = '00000000-0000-0000-0000-000000000000';
    final cid = await _companyId();
    final profile = await SupabaseService.fetchCurrentUserProfile();
    final isSuper = profile?.isSuperAdmin == true;

    if (isSuper && cid != null && cid != maviCompanyId) {
      final primary = await fetchRecentEvents(
        limit: limit,
        includeArchived: includeArchived,
        companyIdOverride: cid,
      );
      final mavi = await fetchRecentEvents(
        limit: limit,
        includeArchived: includeArchived,
        companyIdOverride: maviCompanyId,
      );
      final byId = <String, VisionEvent>{};
      for (final e in [...mavi, ...primary]) {
        if (e.eventType == 'sorting_clip') byId[e.id] = e;
      }
      final merged = byId.values.toList()
        ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      return merged.take(limit).toList();
    }

    final events = await fetchRecentEvents(
      limit: limit,
      includeArchived: includeArchived,
    );
    return events.where((e) => e.eventType == 'sorting_clip').toList();
  }

  Future<VisionEvent> markSortingEventViewed(String eventId) async {
    final row = await _client.rpc(
      'mark_vision_event_viewed',
      params: {'p_event_id': eventId},
    ) as Map<String, dynamic>;
    return VisionEvent.fromRow(row);
  }

  Future<VisionEvent> setSortingEventArchived(
    String eventId, {
    required bool archived,
  }) async {
    final row = await _client.rpc(
      'set_vision_event_archived',
      params: {
        'p_event_id': eventId,
        'p_archived': archived,
      },
    ) as Map<String, dynamic>;
    return VisionEvent.fromRow(row);
  }

  /// Merk avvik som riktig (falsk alarm) eller feil — med valgfri kommentar.
  Future<VisionEvent> markSortingFeedback(
    String eventId, {
    String label = 'correct',
    String? note,
  }) async {
    final row = await _client.rpc(
      'mark_vision_sorting_feedback',
      params: {
        'p_event_id': eventId,
        'p_label': label,
        'p_note': note,
      },
    ) as Map<String, dynamic>;
    return VisionEvent.fromRow(row);
  }

  Future<VisionEvent> softDeleteSortingEvent(String eventId) async {
    final row = await _client.rpc(
      'soft_delete_vision_event',
      params: {'p_event_id': eventId},
    ) as Map<String, dynamic>;
    return VisionEvent.fromRow(row);
  }

  Future<VisionLearnSession> startLearnMode(String cameraId) async {
    final row = await _client.rpc(
      'start_vision_learn_mode',
      params: {'p_camera_id': cameraId},
    ) as Map<String, dynamic>;
    return VisionLearnSession.fromRow(row);
  }

  Future<VisionLearnSession> stopLearnMode(String cameraId) async {
    final row = await _client.rpc(
      'stop_vision_learn_mode',
      params: {'p_camera_id': cameraId},
    ) as Map<String, dynamic>;
    return VisionLearnSession.fromRow(row);
  }

  Future<List<VisionLearnSession>> fetchLearnSessions({
    int limit = 40,
  }) async {
    final cid = await _companyId();
    if (cid == null) return [];
    final rows = await _client
        .from('vision_learn_sessions')
        .select()
        .eq('company_id', cid)
        .order('started_at', ascending: false)
        .limit(limit) as List<dynamic>;
    return rows
        .map((r) =>
            VisionLearnSession.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<VisionLearnSession?> fetchLearnSession(String sessionId) async {
    final row = await _client
        .from('vision_learn_sessions')
        .select()
        .eq('id', sessionId)
        .maybeSingle();
    if (row == null) return null;
    return VisionLearnSession.fromRow(Map<String, dynamic>.from(row));
  }

  Future<void> addLearnLabel({
    required String sessionId,
    required String label,
    String? zone,
    String? reason,
    String? note,
    double? timestampInVideoSec,
  }) async {
    await _client.rpc(
      'add_vision_learn_label',
      params: {
        'p_session_id': sessionId,
        'p_label': label,
        'p_zone': zone,
        'p_reason': reason,
        'p_note': note,
        'p_timestamp_in_video_sec': timestampInVideoSec,
      },
    );
  }

  Future<List<VisionLearnLabel>> fetchLearnLabels(String sessionId) async {
    final rows = await _client
        .from('vision_learn_labels')
        .select()
        .eq('session_id', sessionId)
        .order('created_at', ascending: false) as List<dynamic>;
    return rows
        .map((r) =>
            VisionLearnLabel.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Fersk midlertidig Dropbox-lenke for lagret sti (lære-session m.m.).
  Future<VisionMediaLink?> resolveDropboxPathLink(
    String path, {
    String? sessionId,
  }) async {
    final session = _client.auth.currentSession;
    if (session == null) return null;
    final params = <String, String>{
      'action': 'media_link',
      'path': path,
    };
    if (sessionId != null && sessionId.isNotEmpty) {
      params['session_id'] = sessionId;
    }
    final uri = Uri.parse(
      '${SupabaseConfig.url}/functions/v1/vision-camera',
    ).replace(queryParameters: params);
    try {
      final res = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': SupabaseConfig.anonKey,
        },
      );
      if (res.statusCode != 200) {
        debugPrint('resolveDropboxPathLink ${res.statusCode}: ${res.body}');
        return null;
      }
      final data = jsonDecode(res.body);
      if (data is! Map) return null;
      final link = data['temporary_link']?.toString();
      if (link == null || !link.startsWith('http')) return null;
      final kind = data['kind']?.toString() == 'image' ? 'image' : 'video';
      return VisionMediaLink(url: link, kind: kind);
    } catch (e) {
      debugPrint('resolveDropboxPathLink error: $e');
      return null;
    }
  }

  /// Fersk midlertidig Dropbox-lenke for klipp (video eller bilde).
  Future<VisionMediaLink?> resolveEventMediaLink(String eventId) async {
    final session = _client.auth.currentSession;
    if (session == null) return null;

    final uri = Uri.parse(
      '${SupabaseConfig.url}/functions/v1/vision-camera'
      '?action=media_link&event_id=${Uri.encodeQueryComponent(eventId)}',
    );
    try {
      final res = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': SupabaseConfig.anonKey,
        },
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data is! Map) return null;
      final link = data['temporary_link']?.toString();
      if (link == null || !link.startsWith('http')) return null;
      final kind = data['kind']?.toString() == 'image' ? 'image' : 'video';
      return VisionMediaLink(url: link, kind: kind);
    } catch (_) {
      return null;
    }
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
      '${SupabaseConfig.url}/functions/v1/vision-camera?action=live&camera_id=$cameraId',
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
      // Fallback: direkte snapshot fra edge (kun hvis edge når kamera-LAN).
      final snapUri = Uri.parse(
        '${SupabaseConfig.url}/functions/v1/vision-camera?action=snapshot&camera_id=$cameraId',
      );
      final snap = await http.get(
        snapUri,
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': SupabaseConfig.anonKey,
        },
      );
      if (snap.statusCode == 200 && snap.bodyBytes.isNotEmpty) {
        return LiveFrameResult(bytes: snap.bodyBytes, source: 'edge');
      }
      if (res.statusCode == 404 || snap.statusCode == 404) {
        return _fetchLocalWorkerFallback(null);
      }
      if (kDebugMode) {
        return _fetchLocalWorkerFallback(null);
      }
      return LiveFrameResult(
        error: res.statusCode == 404
            ? 'Ingen live-frame ennå — start worker på jobb-PC'
            : 'Kobler til kamera…',
      );
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
