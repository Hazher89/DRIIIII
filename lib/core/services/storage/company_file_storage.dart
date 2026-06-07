import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/storage_path_sanitizer.dart';
import '../supabase_service.dart';
import 'dropbox_storage_modules.dart';

/// Resultat fra opplasting — Supabase eller Dropbox.
class StoredFileResult {
  final String provider;
  final String path;
  final String? publicOrSignedUrl;
  final int sizeBytes;

  const StoredFileResult({
    required this.provider,
    required this.path,
    this.publicOrSignedUrl,
    required this.sizeBytes,
  });

  bool get isDropbox => provider == 'dropbox';
}

/// All filopplasting går til Dropbox når bedriften er koblet.
/// Supabase brukes kun når Dropbox ikke er satt opp ennå.
class CompanyFileStorage {
  static const int defaultThresholdBytes = 0;

  static SupabaseClient get _client => Supabase.instance.client;

  static const String dropboxUrlScheme = 'dropbox://';

  static bool isDropboxReference(String ref) {
    final r = ref.trim();
    return r.startsWith(dropboxUrlScheme) || isDropboxPath(r);
  }

  static String toStorageReference(StoredFileResult result) {
    if (result.isDropbox) return '$dropboxUrlScheme${result.path}';
    return result.publicOrSignedUrl ?? result.path;
  }

  /// Løs lagret referanse til visbar URL (midlertidig lenke for Dropbox).
  static Future<String> resolveDisplayUrl(String ref) async {
    final r = ref.trim();
    if (r.startsWith(dropboxUrlScheme)) {
      return getDropboxTemporaryLink(r.substring(dropboxUrlScheme.length));
    }
    if (isDropboxPath(r)) return getDropboxTemporaryLink(r);
    return r;
  }

  static bool isModuleEnabled(
    Map<String, dynamic>? status,
    String category,
  ) {
    final mod = DropboxStorageModule.fromCategory(category);
    if (mod == null) return true;
    final modules = DropboxStorageModule.fromStatusJson(status);
    return modules[mod.key] ?? true;
  }

  static Future<Map<String, bool>> updateStorageModules(
    Map<String, bool> modules,
  ) async {
    final body = <String, dynamic>{};
    for (final m in DropboxStorageModule.values) {
      if (modules.containsKey(m.key)) body[m.key] = modules[m.key];
    }
    final res = await _client.rpc('set_company_dropbox_storage_modules', params: {
      'p_modules': body,
    });
    if (res is Map) {
      return DropboxStorageModule.fromStatusJson({'storage_modules': res});
    }
    return modules;
  }

  static bool isDropboxPath(String path) {
    final p = path.trim();
    if (p.startsWith('/DriftPro') || p.startsWith('DriftPro/')) return true;
    // App folder (rot = /): /company_<uuid>/routes/...
    return RegExp(r'^/company_[0-9a-f-]{36}/').hasMatch(p);
  }

  /// Tilgjengelig for alle innloggede (ikke bare admin).
  static Future<bool> isDropboxConnected() async {
    try {
      final res = await _client.rpc('is_company_dropbox_connected');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Full status — kun administrator (innstillinger-skjerm).
  static Future<Map<String, dynamic>?> dropboxStatus() async {
    try {
      final res = await _client.rpc('get_company_dropbox_status');
      if (res is Map) return Map<String, dynamic>.from(res);
      return null;
    } catch (_) {
      return null;
    }
  }

  static const _productionAppUrl = 'https://driftpro.no';

  /// OAuth-retur: driftpro.no i prod, localhost kun ved lokal utvikling.
  static String _dropboxOAuthReturnUrl() {
    final host = Uri.base.host.toLowerCase();
    if (host == 'localhost' || host == '127.0.0.1') {
      return Uri.base.origin;
    }
    return _productionAppUrl;
  }

  static Future<String?> getDropboxAuthUrl({String? returnUrl}) async {
    final origin = (returnUrl ?? _dropboxOAuthReturnUrl()).trim();
    final res = await _client.functions.invoke(
      'dropbox-storage',
      method: HttpMethod.get,
      queryParameters: {
        'action': 'auth_url',
        'return_url': origin,
      },
    );
    final data = res.data;
    if (data is Map && data['auth_url'] is String) {
      return data['auth_url'] as String;
    }
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    return null;
  }

  static Future<void> disconnectDropbox() async {
    await _client.rpc('disconnect_company_dropbox');
  }

  /// Lagre fil — Dropbox når koblet, ellers Supabase.
  static Future<StoredFileResult> upload({
    required String supabaseBucket,
    required String storagePath,
    required Uint8List bytes,
    required String category,
    String? fileName,
  }) async {
    final connected = await isDropboxConnected();
    final safePath = StoragePathSanitizer.storagePath(storagePath);
    final name = fileName ?? safePath.split('/').last;

    if (!connected) {
      return _uploadSupabase(supabaseBucket, storagePath, bytes);
    }

    final safeName = StoragePathSanitizer.fileName(name);
    final b64 = base64Encode(bytes);
    try {
      final res = await _client.functions.invoke(
        'dropbox-storage',
        body: {
          'file_name': safeName,
          'category': category,
          'bytes_base64': b64,
        },
        queryParameters: {'action': 'upload'},
      );
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        return StoredFileResult(
          provider: 'dropbox',
          path: data['path'] as String? ?? '',
          publicOrSignedUrl: data['temporary_link'] as String?,
          sizeBytes: bytes.length,
        );
      }

      final reason = data is Map
          ? (data['error'] ?? data['reason'] ?? 'ukjent feil').toString()
          : 'Dropbox-opplasting feilet';
      if (kDebugMode) {
        debugPrint('Dropbox upload feilet ($reason) — faller tilbake til Supabase.');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Dropbox upload exception ($e) — faller tilbake til Supabase.');
      }
    }

    return _uploadSupabase(supabaseBucket, safePath, bytes);
  }

  static Future<StoredFileResult> _uploadSupabase(
    String bucket,
    String path,
    Uint8List bytes,
  ) async {
    final safePath = StoragePathSanitizer.storagePath(path);
    final url = await SupabaseService.uploadFile(bucket, safePath, bytes);
    return StoredFileResult(
      provider: 'supabase',
      path: safePath,
      publicOrSignedUrl: url,
      sizeBytes: bytes.length,
    );
  }

  /// Hent midlertidig lenke for Dropbox-fil.
  static Future<String> getDropboxTemporaryLink(String dropboxPath) async {
    final res = await _client.functions.invoke(
      'dropbox-storage',
      body: {'path': dropboxPath},
      queryParameters: {'action': 'temporary_link'},
    );
    final data = res.data;
    if (data is Map && data['link'] is String) return data['link'] as String;
    throw Exception(data is Map ? data['error']?.toString() ?? 'Ingen lenke' : 'Dropbox-feil');
  }
}
