/// IP-kamera for vision monitor (PPE / parkering).
class VisionCamera {
  const VisionCamera({
    required this.id,
    required this.companyId,
    required this.name,
    required this.host,
    this.httpPort = 80,
    this.cameraUser = 'admin',
    this.hasPassword = false,
    this.snapshotPath = '/ISAPI/Streaming/channels/101/picture',
    this.eventType = 'ppe_violation',
    this.enabled = true,
    this.learnMode = false,
    this.learnSessionId,
    this.learnStartedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String companyId;
  final String name;
  final String host;
  final int httpPort;
  final String cameraUser;
  final bool hasPassword;
  final String snapshotPath;
  final String eventType;
  final bool enabled;
  final bool learnMode;
  final String? learnSessionId;
  final DateTime? learnStartedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get baseUrl => 'http://$host${httpPort == 80 ? '' : ':$httpPort'}';

  String get snapshotUrl => '$baseUrl$snapshotPath';

  String get eventTypeLabel => switch (eventType) {
        'ppe_violation' => 'PPE-brudd',
        'uniform_violation' => 'Uniform-brudd',
        'sorting_clip' => 'Søppelsortering',
        'parking_entry' => 'Parkering inn',
        'parking_exit' => 'Parkering ut',
        _ => eventType,
      };

  factory VisionCamera.fromJson(Map<String, dynamic> json) {
    DateTime? parseTs(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return VisionCamera(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      name: json['name'] as String? ?? 'Kamera',
      host: json['host'] as String,
      httpPort: (json['http_port'] as num?)?.toInt() ?? 80,
      cameraUser: json['camera_user'] as String? ?? 'admin',
      hasPassword: json['has_password'] == true,
      snapshotPath: json['snapshot_path'] as String? ??
          '/ISAPI/Streaming/channels/101/picture',
      eventType: json['event_type'] as String? ?? 'ppe_violation',
      enabled: json['enabled'] != false,
      learnMode: json['learn_mode'] == true,
      learnSessionId: json['learn_session_id'] as String?,
      learnStartedAt: parseTs(json['learn_started_at']),
      createdAt: parseTs(json['created_at']),
      updatedAt: parseTs(json['updated_at']),
    );
  }

  Map<String, dynamic> toInsertJson({
    required String companyId,
    String? cameraPassword,
  }) {
    return {
      'company_id': companyId,
      'name': name,
      'host': host,
      'http_port': httpPort,
      'camera_user': cameraUser,
      if (cameraPassword != null && cameraPassword.isNotEmpty)
        'camera_password': cameraPassword,
      'snapshot_path': snapshotPath,
      'event_type': eventType,
      'enabled': enabled,
    };
  }

  VisionCamera copyWith({
    String? name,
    String? host,
    int? httpPort,
    String? cameraUser,
    bool? hasPassword,
    String? snapshotPath,
    String? eventType,
    bool? enabled,
    bool? learnMode,
    String? learnSessionId,
    DateTime? learnStartedAt,
  }) {
    return VisionCamera(
      id: id,
      companyId: companyId,
      name: name ?? this.name,
      host: host ?? this.host,
      httpPort: httpPort ?? this.httpPort,
      cameraUser: cameraUser ?? this.cameraUser,
      hasPassword: hasPassword ?? this.hasPassword,
      snapshotPath: snapshotPath ?? this.snapshotPath,
      eventType: eventType ?? this.eventType,
      enabled: enabled ?? this.enabled,
      learnMode: learnMode ?? this.learnMode,
      learnSessionId: learnSessionId ?? this.learnSessionId,
      learnStartedAt: learnStartedAt ?? this.learnStartedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class VisionEvent {
  const VisionEvent({
    required this.id,
    required this.cameraId,
    required this.eventType,
    required this.status,
    required this.dropboxImageUrl,
    required this.occurredAt,
    this.metadata = const {},
    this.dropboxPath,
    this.viewedAt,
    this.archivedAt,
  });

  final String id;
  final String cameraId;
  final String eventType;
  final String status;
  final String dropboxImageUrl;
  final DateTime occurredAt;
  final Map<String, dynamic> metadata;
  final String? dropboxPath;
  final DateTime? viewedAt;
  final DateTime? archivedAt;

  bool get isViewed => viewedAt != null;
  bool get isArchived => archivedAt != null;
  bool get isDismissed => status == 'dismissed';

  bool get missingLogo => metadata['missing_logo'] == true;
  bool get missingShoes => metadata['missing_shoes'] == true;

  String? get videoUrl {
    final v = metadata['dropbox_video_url']?.toString();
    if (v != null && v.startsWith('http')) return v;
    final p = metadata['video_path']?.toString();
    if (p != null && p.startsWith('http')) return p;
    return null;
  }

  String? get videoDropboxPath {
    final dedicated = metadata['dropbox_video_path']?.toString();
    if (dedicated != null && dedicated.isNotEmpty) return dedicated;
    final path = dropboxPath;
    if (path != null && _isVideoPath(path)) return path;
    return null;
  }

  /// Kun ekte videoklipp (mp4/mov) — ikke stillbilder.
  bool get hasVideoClip {
    if (videoUrl != null) return true;
    final path = metadata['dropbox_video_path']?.toString();
    if (path != null && _isVideoPath(path)) return true;
    if (dropboxPath != null && _isVideoPath(dropboxPath!)) return true;
    return false;
  }

  static bool _isVideoPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4v');
  }

  String? get clipDurationLabel {
    final before = metadata['clip_seconds_before'];
    final after = metadata['clip_seconds_after'];
    if (before is! num || after is! num) return null;
    final total = (before + after).round();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  List<String> get insightChips {
    final out = <String>[];
    final zone = metadata['zone']?.toString();
    final reason = metadata['reason']?.toString();
    final label = metadata['label']?.toString();
    final conf = metadata['confidence'];
    final frames = metadata['frame_count'];
    final before = metadata['clip_seconds_before'];
    final after = metadata['clip_seconds_after'];
    if (zone != null && zone.isNotEmpty) out.add(zone);
    if (reason != null && reason.isNotEmpty) out.add(reason);
    if (label != null && label.isNotEmpty) out.add(label);
    if (conf is num) out.add('treff ${(conf * 100).round()}%');
    if (before is num && after is num) {
      out.add('${before.round()}+${after.round()}s');
    }
    if (frames is num) out.add('$frames bilder');
    return out;
  }

  String get violationSummary {
    if (missingLogo && missingShoes) return 'Mangler logo og vernesko';
    if (missingLogo) return 'Mangler MAVI-logo';
    if (missingShoes) return 'Mangler vernesko';
    if (eventType == 'sorting_clip') {
      final reason = metadata['reason']?.toString();
      final zone = metadata['zone']?.toString();
      String label;
      switch (reason) {
        case 'unflattened_cardboard':
          label = 'Ubrettet/stor eske i papp-container';
        case 'cardboard_in_wrong_bin':
          label = 'Eske kastet i annet-container';
        case 'wrong_material_in_papp':
          label = 'Feil materiale i papp-container';
        case 'bulky_packaging':
          label = 'Stor/full emballasje';
        case 'cardboard':
          label = 'Brun eske';
        default:
          label = 'Søppelsortering-avvik';
      }
      return zone != null && zone.isNotEmpty ? '$label ($zone)' : label;
    }
    return eventType;
  }

  VisionEvent copyWith({
    DateTime? viewedAt,
    DateTime? archivedAt,
    String? status,
    bool clearArchived = false,
  }) {
    return VisionEvent(
      id: id,
      cameraId: cameraId,
      eventType: eventType,
      status: status ?? this.status,
      dropboxImageUrl: dropboxImageUrl,
      occurredAt: occurredAt,
      metadata: metadata,
      dropboxPath: dropboxPath,
      viewedAt: viewedAt ?? this.viewedAt,
      archivedAt: clearArchived ? null : (archivedAt ?? this.archivedAt),
    );
  }

  factory VisionEvent.fromRow(Map<String, dynamic> row) {
    DateTime? parseTs(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return VisionEvent(
      id: row['id'] as String,
      cameraId: row['camera_id'] as String,
      eventType: row['event_type'] as String? ?? '',
      status: row['status'] as String? ?? 'open',
      dropboxImageUrl: row['dropbox_image_url'] as String? ?? '',
      occurredAt: DateTime.parse(row['occurred_at'] as String),
      metadata: Map<String, dynamic>.from(row['metadata'] as Map? ?? {}),
      dropboxPath: row['dropbox_path'] as String?,
      viewedAt: parseTs(row['viewed_at']),
      archivedAt: parseTs(row['archived_at']),
    );
  }
}
