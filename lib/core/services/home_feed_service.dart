import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/home_feed_item.dart';
import '../../models/home_feed_layout_config.dart';
import '../services/storage/company_file_storage.dart';
import '../services/supabase_service.dart';
import 'storage/storage_file_access.dart';

class HomeFeedService {
  HomeFeedService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<List<HomeFeedItem>> fetchFeed(HomeFeedAudience audience) async {
    final res = await _client.rpc('get_home_feed', params: {
      'p_audience': audience.dbValue,
    });
    if (res is! List) return const [];
    return res
        .whereType<Map>()
        .map((e) => HomeFeedItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.storagePath.isNotEmpty)
        .toList();
  }

  static Future<List<HomeFeedItem>> fetchAllForAdmin(
    HomeFeedAudience audience,
  ) async {
    final companyId = await SupabaseService.getCurrentCompanyId();
    if (companyId == null) return const [];

    final res = await _client
        .from('company_home_feed_items')
        .select()
        .eq('company_id', companyId)
        .eq('audience', audience.dbValue)
        .order('sort_order')
        .order('created_at', ascending: false);

    return (res as List)
        .whereType<Map>()
        .map((e) => HomeFeedItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
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
    required String storagePath,
    required String title,
    String? caption,
    String? fileName,
    String? mimeType,
    int sortOrder = 0,
    HomeFeedLayoutConfig layoutConfig = HomeFeedLayoutConfig.defaults,
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
      'storage_path': storagePath,
      'file_name': fileName,
      'mime_type': mimeType,
      'sort_order': sortOrder,
      'is_active': true,
      'layout_config': layoutConfig.toJson(),
    };

    final res = await _client
        .from('company_home_feed_items')
        .insert(payload)
        .select()
        .single();

    return HomeFeedItem.fromJson(Map<String, dynamic>.from(res));
  }

  static Future<HomeFeedItem> updateItem(HomeFeedItem item) async {
    final res = await _client
        .from('company_home_feed_items')
        .update(item.toUpdateJson())
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
      final item = items[i].copyWith(sortOrder: i);
      if (item.sortOrder == items[i].sortOrder) continue;
      await _client
          .from('company_home_feed_items')
          .update({'sort_order': i})
          .eq('id', item.id);
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
}
