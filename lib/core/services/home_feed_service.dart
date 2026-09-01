import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/home_feed_content_config.dart';
import '../../models/home_feed_item.dart';
import '../../models/home_feed_layout_config.dart';
import '../services/storage/company_file_storage.dart';
import '../services/supabase_service.dart';
import 'storage/storage_file_access.dart';

class HomeFeedService {
  HomeFeedService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<List<HomeFeedItem>> fetchFeed(
    HomeFeedAudience audience, {
    String? portal,
  }) async {
    final res = await _client.rpc('get_home_feed', params: {
      'p_audience': audience.dbValue,
      'p_portal': portal,
    });
    if (res is! List) return const [];

    final items = <HomeFeedItem>[];
    for (final row in res.whereType<Map>()) {
      var item = HomeFeedItem.fromJson(Map<String, dynamic>.from(row));
      if (item.contentType == HomeFeedContentType.carousel) {
        final slides = await fetchCarouselSlides(item.id);
        item = item.copyWith(carouselSlides: slides);
      }
      items.add(item);
    }
    return items;
  }

  static Future<List<HomeFeedItem>> fetchCarouselSlides(String parentId) async {
    final res = await _client.rpc('get_home_feed_carousel_slides', params: {
      'p_parent_id': parentId,
    });
    if (res is! List) return const [];
    return res
        .whereType<Map>()
        .map((e) => HomeFeedItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<List<HomeFeedItem>> fetchAllForAdmin(
    HomeFeedAudience audience, {
    bool includeCarouselChildren = true,
  }) async {
    final companyId = await SupabaseService.getCurrentCompanyId();
    if (companyId == null) return const [];

    final res = await _client
        .from('company_home_feed_items')
        .select()
        .eq('company_id', companyId)
        .eq('audience', audience.dbValue)
        .order('sort_order')
        .order('created_at', ascending: false);

    final all = (res as List)
        .whereType<Map>()
        .map((e) => HomeFeedItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    if (!includeCarouselChildren) {
      return all.where((e) => e.isTopLevel).toList();
    }

    final childrenByParent = <String, List<HomeFeedItem>>{};
    final topLevel = <HomeFeedItem>[];
    for (final item in all) {
      if (item.parentId != null) {
        childrenByParent.putIfAbsent(item.parentId!, () => []).add(item);
      } else {
        topLevel.add(item);
      }
    }

    return topLevel.map((item) {
      if (item.contentType != HomeFeedContentType.carousel) return item;
      final slides = childrenByParent[item.id] ?? const [];
      slides.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return item.copyWith(carouselSlides: slides);
    }).toList();
  }

  static RealtimeChannel subscribe({
    required HomeFeedAudience audience,
    required void Function() onChanged,
  }) {
    final channel = _client.channel('home_feed_${audience.dbValue}');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'company_home_feed_items',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'audience',
        value: audience.dbValue,
      ),
      callback: (_) => onChanged(),
    );
    channel.subscribe();
    return channel;
  }

  static void unsubscribe(RealtimeChannel? channel) {
    if (channel == null) return;
    _client.removeChannel(channel);
  }

  static Future<String> uploadMedia({
    required HomeFeedAudience audience,
    required HomeFeedContentType contentType,
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    final companyId = await SupabaseService.getCurrentCompanyId();
    if (companyId == null) {
      throw Exception('Fant ingen bedrift.');
    }

    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath =
        'company_$companyId/home_feed/${audience.dbValue}/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    final stored = await CompanyFileStorage.upload(
      supabaseBucket: 'documents',
      storagePath: storagePath,
      bytes: bytes,
      category: 'home_feed',
      fileName: safeName,
    );

    return CompanyFileStorage.toStorageReference(stored);
  }

  static Future<HomeFeedItem> createItem({
    required HomeFeedAudience audience,
    required HomeFeedContentType contentType,
    String storagePath = '',
    required String title,
    String? caption,
    String? fileName,
    String? mimeType,
    int sortOrder = 0,
    HomeFeedLayoutConfig layoutConfig = HomeFeedLayoutConfig.defaults,
    HomeFeedContentConfig contentConfig = HomeFeedContentConfig.empty,
    String? parentId,
    DateTime? scheduleStart,
    DateTime? scheduleEnd,
    List<HomeFeedTargetPortal> targetPortals = const [],
    int priority = 0,
    bool pinned = false,
    bool isActive = true,
  }) async {
    final companyId = await SupabaseService.getCurrentCompanyId();
    if (companyId == null) {
      throw Exception('Fant ingen bedrift.');
    }

    final payload = {
      'company_id': companyId,
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
        'schedule_start': scheduleStart.toUtc().toIso8601String(),
      if (scheduleEnd != null)
        'schedule_end': scheduleEnd.toUtc().toIso8601String(),
      if (targetPortals.isNotEmpty)
        'target_portals':
            targetPortals.map((e) => e.dbValue).toList(growable: false),
      'priority': priority,
      'pinned': pinned,
    };

    final res = await _client
        .from('company_home_feed_items')
        .insert(payload)
        .select()
        .single();

    return HomeFeedItem.fromJson(Map<String, dynamic>.from(res));
  }

  static Future<HomeFeedItem> createTextBlock({
    required HomeFeedAudience audience,
    required String title,
    String body = '',
    String? caption,
    int sortOrder = 0,
    HomeFeedLayoutConfig? layoutConfig,
    HomeFeedThemePreset theme = HomeFeedThemePreset.maviGreen,
  }) {
    return createItem(
      audience: audience,
      contentType: HomeFeedContentType.text,
      title: title,
      caption: caption,
      sortOrder: sortOrder,
      layoutConfig: layoutConfig ?? HomeFeedLayoutConfig.defaults,
      contentConfig: HomeFeedContentConfig(
        textBlock: HomeFeedTextBlockConfig(body: body, theme: theme),
      ),
    );
  }

  static Future<HomeFeedItem> createYoutubeBlock({
    required HomeFeedAudience audience,
    required String title,
    required String videoUrl,
    String? caption,
    int sortOrder = 0,
  }) {
    return createItem(
      audience: audience,
      contentType: HomeFeedContentType.youtube,
      title: title,
      caption: caption,
      sortOrder: sortOrder,
      contentConfig: HomeFeedContentConfig(
        youtube: HomeFeedYoutubeConfig(videoUrl: videoUrl),
      ),
    );
  }

  static Future<HomeFeedItem> createLinkBlock({
    required HomeFeedAudience audience,
    required String title,
    required String url,
    String buttonLabel = 'Les mer',
    String? caption,
    int sortOrder = 0,
  }) {
    return createItem(
      audience: audience,
      contentType: HomeFeedContentType.link,
      title: title,
      caption: caption,
      sortOrder: sortOrder,
      contentConfig: HomeFeedContentConfig(
        link: HomeFeedLinkConfig(url: url, buttonLabel: buttonLabel),
      ),
    );
  }

  static Future<HomeFeedItem> createSpacer({
    required HomeFeedAudience audience,
    double heightApp = 24,
    double heightWeb = 32,
    int sortOrder = 0,
  }) {
    return createItem(
      audience: audience,
      contentType: HomeFeedContentType.spacer,
      title: 'Spacer',
      sortOrder: sortOrder,
      contentConfig: HomeFeedContentConfig(
        spacer: HomeFeedSpacerConfig(
          heightApp: heightApp,
          heightWeb: heightWeb,
        ),
      ),
    );
  }

  static Future<HomeFeedItem> createCarousel({
    required HomeFeedAudience audience,
    required String title,
    HomeFeedCarouselMode mode = HomeFeedCarouselMode.manual,
    int intervalMs = 8000,
    int sortOrder = 0,
  }) {
    return createItem(
      audience: audience,
      contentType: HomeFeedContentType.carousel,
      title: title,
      sortOrder: sortOrder,
      contentConfig: HomeFeedContentConfig(
        carousel: HomeFeedCarouselConfig(mode: mode, intervalMs: intervalMs),
      ),
    );
  }

  static Future<void> duplicateToAudience(
    HomeFeedItem item,
    HomeFeedAudience targetAudience,
  ) async {
    final copy = await createItem(
      audience: targetAudience,
      contentType: item.contentType,
      storagePath: item.storagePath,
      title: item.title,
      caption: item.caption,
      fileName: item.fileName,
      mimeType: item.mimeType,
      layoutConfig: item.layoutConfig,
      contentConfig: item.contentConfig,
      scheduleStart: item.scheduleStart,
      scheduleEnd: item.scheduleEnd,
      targetPortals: item.targetPortals,
      priority: item.priority,
      pinned: item.pinned,
    );

    if (item.contentType == HomeFeedContentType.carousel) {
      for (final slide in item.carouselSlides) {
        await createItem(
          audience: targetAudience,
          contentType: slide.contentType,
          storagePath: slide.storagePath,
          title: slide.title,
          caption: slide.caption,
          fileName: slide.fileName,
          mimeType: slide.mimeType,
          layoutConfig: slide.layoutConfig,
          contentConfig: slide.contentConfig,
          parentId: copy.id,
          sortOrder: slide.sortOrder,
        );
      }
    }
  }

  static Future<HomeFeedItem> updateItem(HomeFeedItem item) async {
    final snapshots = List<Map<String, dynamic>>.from(item.versionSnapshots);
    snapshots.insert(0, item.toSnapshotJson());
    if (snapshots.length > 10) snapshots.removeRange(10, snapshots.length);

    final res = await _client
        .from('company_home_feed_items')
        .update(item.copyWith(versionSnapshots: snapshots).toUpdateJson())
        .eq('id', item.id)
        .select()
        .single();

    return HomeFeedItem.fromJson(Map<String, dynamic>.from(res));
  }

  static Future<void> deleteItem(String id) async {
    await _client.from('company_home_feed_items').delete().eq('id', id);
  }

  static Future<void> reorderItems(List<HomeFeedItem> items) async {
    for (var i = 0; i < items.length; i++) {
      await _client
          .from('company_home_feed_items')
          .update({'sort_order': i})
          .eq('id', items[i].id);
    }
  }

  static Future<String?> resolveDisplayUrl(String storagePath) async {
    final raw = storagePath.trim();
    if (raw.isEmpty) return null;
    try {
      return await StorageFileAccess.resolveViewUrl(raw);
    } catch (e) {
      if (e is StorageBytesReady) return null;
      try {
        return await CompanyFileStorage.resolveDisplayUrl(raw);
      } catch (_) {
        return null;
      }
    }
  }

  static HomeFeedContentType? guessContentType(String fileName, {String? mime}) {
    final lower = fileName.toLowerCase();
    final m = mime?.toLowerCase() ?? '';
    if (m.startsWith('image/') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif')) {
      return HomeFeedContentType.image;
    }
    if (m.startsWith('video/') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m4v')) {
      return HomeFeedContentType.video;
    }
    if (lower.endsWith('.pdf') ||
        lower.endsWith('.doc') ||
        lower.endsWith('.docx') ||
        lower.endsWith('.txt') ||
        m.contains('pdf') ||
        m.contains('document')) {
      return HomeFeedContentType.document;
    }
    return null;
  }

  static String? validateYoutubeUrl(String url) {
    return HomeFeedYoutubeConfig.extractYoutubeId(url);
  }
}
