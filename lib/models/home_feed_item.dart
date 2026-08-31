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
  image('image', 'Bilde'),
  video('video', 'Video'),
  document('document', 'Dokument');

  const HomeFeedContentType(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static HomeFeedContentType? fromDb(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'image':
        return HomeFeedContentType.image;
      case 'video':
        return HomeFeedContentType.video;
      case 'document':
        return HomeFeedContentType.document;
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
    required this.storagePath,
    this.caption,
    this.fileName,
    this.mimeType,
    this.sortOrder = 0,
    this.isActive = true,
    this.layoutConfig = HomeFeedLayoutConfig.defaults,
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
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory HomeFeedItem.fromJson(Map<String, dynamic> json) {
    final audience = HomeFeedAudience.fromDb(json['audience'] as String?) ??
        HomeFeedAudience.mavi;
    final contentType =
        HomeFeedContentType.fromDb(json['content_type'] as String?) ??
            HomeFeedContentType.image;

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
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toInsertJson() => {
        'audience': audience.dbValue,
        'content_type': contentType.dbValue,
        'title': title,
        'caption': caption,
        'storage_path': storagePath,
        'file_name': fileName,
        'mime_type': mimeType,
        'sort_order': sortOrder,
        'is_active': isActive,
        'layout_config': layoutConfig.toJson(),
      };

  Map<String, dynamic> toUpdateJson() => {
        'title': title,
        'caption': caption,
        'sort_order': sortOrder,
        'is_active': isActive,
        'layout_config': layoutConfig.toJson(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  HomeFeedItem copyWith({
    String? title,
    String? caption,
    int? sortOrder,
    bool? isActive,
    HomeFeedLayoutConfig? layoutConfig,
  }) {
    return HomeFeedItem(
      id: id,
      companyId: companyId,
      audience: audience,
      contentType: contentType,
      title: title ?? this.title,
      caption: caption ?? this.caption,
      storagePath: storagePath,
      fileName: fileName,
      mimeType: mimeType,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      layoutConfig: layoutConfig ?? this.layoutConfig,
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
