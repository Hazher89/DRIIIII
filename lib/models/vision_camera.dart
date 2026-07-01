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
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get baseUrl => 'http://$host${httpPort == 80 ? '' : ':$httpPort'}';

  String get snapshotUrl => '$baseUrl$snapshotPath';

  String get eventTypeLabel => switch (eventType) {
        'ppe_violation' => 'PPE-brudd',
        'uniform_violation' => 'Uniform-brudd',
        'parking_entry' => 'Parkering inn',
        'parking_exit' => 'Parkering ut',
        _ => eventType,
      };

  factory VisionCamera.fromJson(Map<String, dynamic> json) {
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
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
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
  });

  final String id;
  final String cameraId;
  final String eventType;
  final String status;
  final String dropboxImageUrl;
  final DateTime occurredAt;
  final Map<String, dynamic> metadata;

  bool get missingLogo => metadata['missing_logo'] == true;
  bool get missingShoes => metadata['missing_shoes'] == true;

  String get violationSummary {
    if (missingLogo && missingShoes) return 'Mangler logo og vernesko';
    if (missingLogo) return 'Mangler MAVI-logo';
    if (missingShoes) return 'Mangler vernesko';
    return eventType;
  }

  factory VisionEvent.fromRow(Map<String, dynamic> row) {
    return VisionEvent(
      id: row['id'] as String,
      cameraId: row['camera_id'] as String,
      eventType: row['event_type'] as String? ?? '',
      status: row['status'] as String? ?? 'open',
      dropboxImageUrl: row['dropbox_image_url'] as String? ?? '',
      occurredAt: DateTime.parse(row['occurred_at'] as String),
      metadata: Map<String, dynamic>.from(row['metadata'] as Map? ?? {}),
    );
  }
}
