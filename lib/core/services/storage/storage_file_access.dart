import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/storage_path_sanitizer.dart';
import '../supabase_service.dart';
import 'company_file_storage.dart';

/// Nedlasting og visnings-URL for filer (Supabase legacy + Dropbox).
class StorageFileAccess {
  StorageFileAccess._();

  static SupabaseClient get _client => Supabase.instance.client;

  static const _placeholderCompany = '00000000-0000-0000-0000-000000000000';

  static String remapCompanyPlaceholder(String path, String? companyId) {
    if (companyId == null || companyId.isEmpty) return path;
    return path
        .replaceAll('company_$_placeholderCompany', 'company_$companyId')
        .replaceAll(_placeholderCompany, companyId);
  }

  static String? extractSupabaseDocumentsPath(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (CompanyFileStorage.isDropboxReference(t)) return null;

    if (t.startsWith('http://') || t.startsWith('https://')) {
      final uri = Uri.tryParse(t);
      if (uri == null) return null;
      final segments = uri.pathSegments;
      final idx = segments.indexOf('documents');
      if (idx >= 0 && idx + 1 < segments.length) {
        return Uri.decodeComponent(segments.sublist(idx + 1).join('/'));
      }
      return null;
    }

    if (t.startsWith('dropbox://')) return null;
    if (CompanyFileStorage.isDropboxPath(t)) return null;
    return t.replaceFirst(RegExp(r'^/'), '');
  }

  static List<String> candidateSupabasePaths(
    String raw, {
    String? companyId,
  }) {
    final seen = <String>{};
    void add(String? p) {
      if (p == null) return;
      final t = p.replaceFirst(RegExp(r'^/'), '').trim();
      if (t.isNotEmpty) seen.add(t);
    }

    var base = raw.trim();
    if (base.isEmpty) return const [];

    add(extractSupabaseDocumentsPath(base));
    add(remapCompanyPlaceholder(base, companyId));
    add(extractSupabaseDocumentsPath(remapCompanyPlaceholder(base, companyId)));

    final noPrefix = base.replaceFirst(RegExp(r'^/'), '');
    add(noPrefix);
    add(StoragePathSanitizer.storagePath(noPrefix));
    add(remapCompanyPlaceholder(noPrefix, companyId));
    add(StoragePathSanitizer.storagePath(remapCompanyPlaceholder(noPrefix, companyId)));

    return seen.toList();
  }

  static Future<Uint8List?> downloadBytes(
    String storagePath, {
    String? companyId,
  }) async {
    final raw = storagePath.trim();
    if (raw.isEmpty) return null;

    final cid = companyId ?? await SupabaseService.getCurrentCompanyId();

    if (CompanyFileStorage.isDropboxReference(raw) ||
        CompanyFileStorage.isDropboxPath(raw)) {
      try {
        final dropboxPath = raw.startsWith(CompanyFileStorage.dropboxUrlScheme)
            ? raw.substring(CompanyFileStorage.dropboxUrlScheme.length)
            : raw.startsWith('/')
                ? raw
                : '/$raw';
        final res = await _client.functions.invoke(
          'dropbox-storage',
          body: {'path': dropboxPath},
          queryParameters: {'action': 'download_bytes'},
        );
        final data = res.data;
        if (data is Map && data['ok'] == true && data['bytes_base64'] is String) {
          final bytes = base64Decode(data['bytes_base64'] as String);
          if (bytes.isNotEmpty) return bytes;
        }
      } catch (_) {}
    }

    for (final path in candidateSupabasePaths(raw, companyId: cid)) {
      try {
        final bytes = await _client.storage.from('documents').download(path);
        if (bytes.isNotEmpty) return bytes;
      } catch (_) {}
    }

    try {
      final url = await _signedUrlForPath(raw, companyId: cid);
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        return res.bodyBytes;
      }
    } catch (_) {}

    return null;
  }

  static bool isSupabaseStorageUrl(String raw) {
    final t = raw.trim();
    return t.contains('/storage/v1/object/');
  }

  static Future<String> resolveViewUrl(
    String storagePath, {
    String? companyId,
  }) async {
    final raw = storagePath.trim();
    if (raw.isEmpty) throw ArgumentError('Sti mangler');

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      if (isSupabaseStorageUrl(raw)) {
        final inner = extractSupabaseDocumentsPath(raw);
        if (inner != null && inner.isNotEmpty) {
          try {
            return await _signedUrlForPath(inner, companyId: companyId);
          } catch (_) {
            final bytes = await downloadBytes(inner, companyId: companyId);
            if (bytes != null && bytes.isNotEmpty) {
              throw StorageBytesReady(bytes);
            }
          }
        }
      }
      if (!isSupabaseStorageUrl(raw)) return raw;
      throw StateError('Kunne ikke åpne lagret fil (ugyldig Supabase-lenke)');
    }

    if (CompanyFileStorage.isDropboxReference(raw) ||
        CompanyFileStorage.isDropboxPath(raw)) {
      try {
        return await CompanyFileStorage.resolveDisplayUrl(raw);
      } catch (_) {
        final bytes = await downloadBytes(raw, companyId: companyId);
        if (bytes != null && bytes.isNotEmpty) {
          throw StorageBytesReady(bytes);
        }
        rethrow;
      }
    }

    try {
      return await _signedUrlForPath(raw, companyId: companyId);
    } catch (_) {
      final bytes = await downloadBytes(raw, companyId: companyId);
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Kunne ikke hente fil fra lagring');
      }
      throw StorageBytesReady(bytes);
    }
  }

  static Future<String> _signedUrlForPath(
    String raw, {
    String? companyId,
  }) async {
    final cid = companyId ?? await SupabaseService.getCurrentCompanyId();
    for (final path in candidateSupabasePaths(raw, companyId: cid)) {
      try {
        return await _client.storage.from('documents').createSignedUrl(path, 3600);
      } catch (_) {}
    }
    throw StateError('InvalidKey');
  }
}

/// Signal at fil ble hentet som bytes (signed URL feilet pga. legacy-sti).
class StorageBytesReady implements Exception {
  final Uint8List bytes;
  StorageBytesReady(this.bytes);
}
