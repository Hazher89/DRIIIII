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

/// Feil når Dropbox mangler eller opplasting feilet (ingen stille Supabase-fallback).
class DropboxUploadException implements Exception {
  DropboxUploadException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// All nye filopplastinger går til Dropbox (web, iOS, Android).
/// Supabase er backend (auth/DB); Supabase Storage brukes ikke for nye filer.
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
    // Lagre relativ sti — ikke public URL (bucket kan være privat / mangler).
    return result.path;
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
    // App-folder-sti: /company_<uuid>/…
    if (p.startsWith('/company_') || p.startsWith('company_')) return true;
    return false;
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

  /// Lås Dropbox mot frakobling (standard). Kun superadmin kan låse opp.
  static Future<void> setDisconnectLocked({
    required bool locked,
    String? confirmPhrase,
  }) async {
    await _client.rpc('set_company_dropbox_disconnect_lock', params: {
      'p_locked': locked,
      'p_confirm': confirmPhrase,
    });
  }

  /// Soft-frakoblet → aktiv igjen uten ny OAuth.
  static Future<void> reactivateDropbox() async {
    await _client.rpc('reactivate_company_dropbox');
  }

  /// Lagre fil i Dropbox (påkrevd).
  ///
  /// Feiler synlig hvis Dropbox ikke er koblet eller opplasting feiler.
  /// `allowSupabaseFallback` er kun for eksplisitte intern/test-kall.
  static Future<StoredFileResult> upload({
    required String supabaseBucket,
    required String storagePath,
    required Uint8List bytes,
    required String category,
    String? fileName,
    bool allowSupabaseFallback = false,
  }) async {
    final connected = await isDropboxConnected();
    final safePath = StoragePathSanitizer.storagePath(storagePath);
    final name = fileName ?? safePath.split('/').last;

    if (!connected) {
      if (allowSupabaseFallback) {
        debugPrint(
          'Dropbox ikke koblet — tillater Supabase-fallback ($category).',
        );
        return _uploadSupabase(supabaseBucket, safePath, bytes);
      }
      throw DropboxUploadException(
        'Dropbox er ikke koblet. Koble under Mer → Fillagring før du laster opp filer.',
      );
    }

    final safeName = StoragePathSanitizer.fileName(name);
    final b64 = base64Encode(bytes);
    Object? lastError;

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
        final path = (data['path'] as String?)?.trim() ?? '';
        if (path.isEmpty) {
          throw DropboxUploadException('Dropbox returnerte tom filsti.');
        }
        return StoredFileResult(
          provider: 'dropbox',
          path: path,
          publicOrSignedUrl: data['temporary_link'] as String?,
          sizeBytes: bytes.length,
        );
      }

      lastError = data is Map
          ? (data['error'] ?? data['reason'] ?? 'ukjent feil')
          : 'Opplasting til Dropbox feilet';
    } catch (e) {
      lastError = e;
      if (e is DropboxUploadException) rethrow;
    }

    final reason = lastError.toString();
    debugPrint('Dropbox upload feilet ($category): $reason');

    if (allowSupabaseFallback) {
      debugPrint('Tillater Supabase-fallback for $category');
      return _uploadSupabase(supabaseBucket, safePath, bytes);
    }

    throw DropboxUploadException(
      'Kunne ikke lagre filen i Dropbox: $reason. '
      'Sjekk Mer → Fillagring, eller prøv en mindre fil.',
    );
  }

  /// Kun for eksplisitt `allowSupabaseFallback` (test/intern) — ikke nye prod-opplastinger.
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
    throw Exception(data is Map ? data['error']?.toString() ?? 'Ingen lenke' : 'Lagringsfeil');
  }
}
