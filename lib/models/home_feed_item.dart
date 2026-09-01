import 'package:flutter/material.dart';

import 'home_feed_content_config.dart';
import 'home_feed_layout_config.dart';

enum HomeFeedAudience {
  mavi('mavi', 'MAVI ansatte'),
  partner('partner', 'Partnere');

  const HomeFeedAudience(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static HomeFeedAudience? fromDb(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'mavi':
        return HomeFeedAudience.mavi;
      case 'partner':
        return HomeFeedAudience.partner;
      default:
        return null;
    }
  }
}

enum HomeFeedContentType {
  image('image', 'Bilde', Icons.image_outlined),
  video('video', 'Video', Icons.videocam_outlined),
  document('document', 'Dokument', Icons.description_outlined),
  text('text', 'Tekst', Icons.text_fields_outlined),
  youtube('youtube', 'YouTube', Icons.play_circle_outline),
  link('link', 'Lenke / knapp', Icons.link_outlined),
  spacer('spacer', 'Luft / spacer', Icons.space_bar),
  carousel('carousel', 'Karusell', Icons.view_carousel_outlined);

  const HomeFeedContentType(this.dbValue, this.label, this.icon);
  final String dbValue;
  final String label;
  final IconData icon;

  bool get needsMedia =>
      this == image || this == video || this == document;

  static HomeFeedContentType? fromDb(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'image':
        return HomeFeedContentType.image;
      case 'video':
        return HomeFeedContentType.video;
      case 'document':
        return HomeFeedContentType.document;
      case 'text':
        return HomeFeedContentType.text;
      case 'youtube':
        return HomeFeedContentType.youtube;
      case 'link':
        return HomeFeedContentType.link;
      case 'spacer':
        return HomeFeedContentType.spacer;
      case 'carousel':
        return HomeFeedContentType.carousel;
      default:
        return null;
    }
  }
}

class HomeFeedItem {
  const HomeFeedItem({
    required this.id,
    required this.companyId,
    required this.audience,
    required this.contentType,
    required this.title,
    this.storagePath = '',
    this.caption,
    this.fileName,
    this.mimeType,
    this.sortOrder = 0,
    this.isActive = true,
    this.layoutConfig = HomeFeedLayoutConfig.defaults,
    this.contentConfig = HomeFeedContentConfig.empty,
    this.parentId,
    this.scheduleStart,
    this.scheduleEnd,
    this.targetPortals = const [],
    this.priority = 0,
    this.pinned = false,
    this.versionSnapshots = const [],
    this.carouselSlides = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String companyId;
  final HomeFeedAudience audience;
  final HomeFeedContentType contentType;
  final String title;
  final String? caption;
  final String storagePath;
  final String? fileName;
  final String? mimeType;
  final int sortOrder;
  final bool isActive;
  final HomeFeedLayoutConfig layoutConfig;
  final HomeFeedContentConfig contentConfig;
  final String? parentId;
  final DateTime? scheduleStart;
  final DateTime? scheduleEnd;
  final List<HomeFeedTargetPortal> targetPortals;
  final int priority;
  final bool pinned;
  final List<Map<String, dynamic>> versionSnapshots;
  final List<HomeFeedItem> carouselSlides;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isTopLevel => parentId == null;

  bool get isScheduled => scheduleStart != null || scheduleEnd != null;

  bool isActiveAt(DateTime now) {
    if (!isActive) return false;
    if (scheduleStart != null && now.isBefore(scheduleStart!)) return false;
    if (scheduleEnd != null && now.isAfter(scheduleEnd!)) return false;
    return true;
  }

  bool matchesPortal(String? portal) {
    if (targetPortals.isEmpty || portal == null || portal.isEmpty) {
      return true;
    }
    return targetPortals.any((p) => p.dbValue == portal);
  }

  factory HomeFeedItem.fromJson(Map<String, dynamic> json) {
    final audience = HomeFeedAudience.fromDb(json['audience'] as String?) ??
        HomeFeedAudience.mavi;
    final contentType =
        HomeFeedContentType.fromDb(json['content_type'] as String?) ??
            HomeFeedContentType.image;

    final rawPortals = json['target_portals'];
    final portals = <HomeFeedTargetPortal>[];
    if (rawPortals is List) {
      for (final p in rawPortals) {
        final parsed = HomeFeedTargetPortal.fromDb(p?.toString());
        if (parsed != null) portals.add(parsed);
      }
    }

    final rawVersions = json['version_snapshots'];
    final versions = rawVersions is List
        ? rawVersions
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    return HomeFeedItem(
      id: json['id']?.toString() ?? '',
      companyId: json['company_id']?.toString() ?? '',
      audience: audience,
      contentType: contentType,
      title: (json['title'] as String?)?.trim() ?? '',
      caption: (json['caption'] as String?)?.trim(),
      storagePath: (json['storage_path'] as String?)?.trim() ?? '',
      fileName: (json['file_name'] as String?)?.trim(),
      mimeType: (json['mime_type'] as String?)?.trim(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] != false,
      layoutConfig: HomeFeedLayoutConfig.fromJson(
        json['layout_config'] as Map<String, dynamic>?,
      ),
      contentConfig: HomeFeedContentConfig.fromJson(
        json['content_json'] as Map<String, dynamic>?,
      ),
      parentId: json['parent_id']?.toString(),
      scheduleStart: _parseDate(json['schedule_start']),
      scheduleEnd: _parseDate(json['schedule_end']),
      targetPortals: portals,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      pinned: json['pinned'] == true,
      versionSnapshots: versions,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toInsertJson() => {
        'audience': audience.dbValue,
        'content_type': contentType.dbValue,
        'title': title,
        'caption': caption,
        if (storagePath.isNotEmpty) 'storage_path': storagePath,
        'file_name': fileName,
        'mime_type': mimeType,
        'sort_order': sortOrder,
        'is_active': isActive,
        'layout_config': layoutConfig.toJson(),
        'content_json': contentConfig.toJson(),
        if (parentId != null) 'parent_id': parentId,
        if (scheduleStart != null)
          'schedule_start': scheduleStart!.toUtc().toIso8601String(),
        if (scheduleEnd != null)
          'schedule_end': scheduleEnd!.toUtc().toIso8601String(),
        if (targetPortals.isNotEmpty)
          'target_portals':
              targetPortals.map((e) => e.dbValue).toList(growable: false),
        'priority': priority,
        'pinned': pinned,
      };

  Map<String, dynamic> toUpdateJson() => {
        'title': title,
        'caption': caption,
        'sort_order': sortOrder,
        'is_active': isActive,
        'layout_config': layoutConfig.toJson(),
        'content_json': contentConfig.toJson(),
        if (scheduleStart != null)
          'schedule_start': scheduleStart!.toUtc().toIso8601String(),
        if (scheduleEnd != null)
          'schedule_end': scheduleEnd!.toUtc().toIso8601String(),
        'target_portals':
            targetPortals.map((e) => e.dbValue).toList(growable: false),
        'priority': priority,
        'pinned': pinned,
        'version_snapshots': versionSnapshots,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  Map<String, dynamic> toSnapshotJson() => {
        'title': title,
        'caption': caption,
        'content_type': contentType.dbValue,
        'layout_config': layoutConfig.toJson(),
        'content_json': contentConfig.toJson(),
        'saved_at': DateTime.now().toUtc().toIso8601String(),
      };

  HomeFeedItem copyWith({
    String? title,
    String? caption,
    String? storagePath,
    int? sortOrder,
    bool? isActive,
    HomeFeedLayoutConfig? layoutConfig,
    HomeFeedContentConfig? contentConfig,
    String? parentId,
    DateTime? scheduleStart,
    DateTime? scheduleEnd,
    List<HomeFeedTargetPortal>? targetPortals,
    int? priority,
    bool? pinned,
    List<Map<String, dynamic>>? versionSnapshots,
    List<HomeFeedItem>? carouselSlides,
  }) {
    return HomeFeedItem(
      id: id,
      companyId: companyId,
      audience: audience,
      contentType: contentType,
      title: title ?? this.title,
      caption: caption ?? this.caption,
      storagePath: storagePath ?? this.storagePath,
      fileName: fileName,
      mimeType: mimeType,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      layoutConfig: layoutConfig ?? this.layoutConfig,
      contentConfig: contentConfig ?? this.contentConfig,
      parentId: parentId ?? this.parentId,
      scheduleStart: scheduleStart ?? this.scheduleStart,
      scheduleEnd: scheduleEnd ?? this.scheduleEnd,
      targetPortals: targetPortals ?? this.targetPortals,
      priority: priority ?? this.priority,
      pinned: pinned ?? this.pinned,
      versionSnapshots: versionSnapshots ?? this.versionSnapshots,
      carouselSlides: carouselSlides ?? this.carouselSlides,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw.toString());
  }
}
