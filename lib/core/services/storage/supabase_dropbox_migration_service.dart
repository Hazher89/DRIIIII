import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_service.dart';
import '../../utils/storage_path_sanitizer.dart';
import 'company_file_storage.dart';
import 'storage_file_access.dart';

class StorageMigrationResult {
  final int migrated;
  final int failed;
  final int skipped;
  final List<String> errors;

  const StorageMigrationResult({
    required this.migrated,
    required this.failed,
    required this.skipped,
    this.errors = const [],
  });

  bool get hasMore => migrated + failed + skipped > 0;
}

/// Engangsmigrering: Supabase Storage → Dropbox + oppdater database.
class SupabaseDropboxMigrationService {
  SupabaseDropboxMigrationService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<StorageMigrationResult> migrateBatch({
    int limit = 25,
  }) async {
    final companyId = await SupabaseService.getCurrentCompanyId();
    if (companyId == null) {
      throw StateError('Fant ikke bedrift');
    }
    if (!await CompanyFileStorage.isDropboxConnected()) {
      throw StateError('Koble Dropbox først under Innstillinger');
    }

    var migrated = 0;
    var failed = 0;
    var skipped = 0;
    final errors = <String>[];

    Future<void> handleRows({
      required String table,
      required String pathColumn,
      required String category,
      required Future<void> Function(String id, String newRef) updateRow,
    }) async {
      final rows = await _client
          .from(table)
          .select('id, $pathColumn')
          .eq('company_id', companyId)
          .not(pathColumn, 'is', null)
          .not(pathColumn, 'ilike', 'dropbox://%')
          .limit(limit) as List<dynamic>;

      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id'] as String;
        final oldPath = (row[pathColumn] as String?)?.trim() ?? '';
        if (oldPath.isEmpty || CompanyFileStorage.isDropboxReference(oldPath)) {
          skipped++;
          continue;
        }

        try {
          final bytes = await StorageFileAccess.downloadBytes(
            oldPath,
            companyId: companyId,
          );
          if (bytes == null || bytes.isEmpty) {
            failed++;
            errors.add('$table/$id: fant ikke fil ($oldPath)');
            continue;
          }

          final fileName = oldPath.split('/').last;
          final safePath = StoragePathSanitizer.storagePath(
            'company_$companyId/migrated/${DateTime.now().millisecondsSinceEpoch}_${StoragePathSanitizer.segment(fileName)}',
          );

          final stored = await CompanyFileStorage.upload(
            supabaseBucket: 'documents',
            storagePath: safePath,
            bytes: bytes,
            category: category,
            fileName: fileName,
          );
          final newRef = CompanyFileStorage.toStorageReference(stored);
          await updateRow(id, newRef);
          migrated++;
        } catch (e) {
          failed++;
          errors.add('$table/$id: $e');
        }
      }
    }

    await handleRows(
      table: 'dms_files',
      pathColumn: 'storage_path',
      category: 'dms',
      updateRow: (id, ref) => _client.from('dms_files').update({
        'storage_path': ref,
        'storage_provider': 'dropbox',
      }).eq('id', id),
    );

    await handleRows(
      table: 'partner_documents',
      pathColumn: 'storage_path',
      category: 'partners',
      updateRow: (id, ref) => _client.from('partner_documents').update({
        'storage_path': ref,
      }).eq('id', id),
    );

    await handleRows(
      table: 'partner_shared_documents',
      pathColumn: 'storage_path',
      category: 'partners',
      updateRow: (id, ref) => _client.from('partner_shared_documents').update({
        'storage_path': ref,
      }).eq('id', id),
    );

    final routeRows = await _client
        .from('partner_route_shares')
        .select('id, pdf_storage_path')
        .eq('company_id', companyId)
        .not('pdf_storage_path', 'is', null)
        .not('pdf_storage_path', 'ilike', 'dropbox://%')
        .limit(limit) as List<dynamic>;

    for (final raw in routeRows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final id = row['id'] as String;
      final oldPath = (row['pdf_storage_path'] as String?)?.trim() ?? '';
      if (oldPath.isEmpty || CompanyFileStorage.isDropboxReference(oldPath)) {
        skipped++;
        continue;
      }
      try {
        final bytes = await StorageFileAccess.downloadBytes(oldPath, companyId: companyId);
        if (bytes == null || bytes.isEmpty) {
          failed++;
          errors.add('partner_route_shares/$id: fant ikke PDF');
          continue;
        }
        final fileName = oldPath.split('/').last;
        final safePath = StoragePathSanitizer.storagePath(
          'company_$companyId/partner_routes/migrated/${DateTime.now().millisecondsSinceEpoch}_${StoragePathSanitizer.segment(fileName)}',
        );
        final stored = await CompanyFileStorage.upload(
          supabaseBucket: 'documents',
          storagePath: safePath,
          bytes: bytes,
          category: 'routes',
          fileName: fileName,
        );
        final newRef = CompanyFileStorage.toStorageReference(stored);
        await _client.from('partner_route_shares').update({
          'pdf_storage_path': newRef,
        }).eq('id', id);
        migrated++;
      } catch (e) {
        failed++;
        errors.add('partner_route_shares/$id: $e');
      }
    }

    return StorageMigrationResult(
      migrated: migrated,
      failed: failed,
      skipped: skipped,
      errors: errors.take(8).toList(),
    );
  }

  static Future<int> countPendingMigration() async {
    final companyId = await SupabaseService.getCurrentCompanyId();
    if (companyId == null) return 0;
    var n = 0;
    for (final spec in [
      ('dms_files', 'storage_path'),
      ('partner_documents', 'storage_path'),
      ('partner_shared_documents', 'storage_path'),
      ('partner_route_shares', 'pdf_storage_path'),
    ]) {
      final rows = await _client
          .from(spec.$1)
          .select('id')
          .eq('company_id', companyId)
          .not(spec.$2, 'is', null)
          .not(spec.$2, 'ilike', 'dropbox://%');
      n += (rows as List).length;
    }
    return n;
  }
}
