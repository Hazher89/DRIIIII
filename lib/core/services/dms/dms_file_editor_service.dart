import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../../models/dms/dms_file.dart';
import '../../utils/file_type_resolver.dart';
import '../storage/company_file_storage.dart';
import 'dms_service.dart';

/// Lagre redigerte dokumenter (erstatt eller ny fil).
class DmsFileEditorService {
  DmsFileEditorService._();

  static Future<DmsFile> replaceFile({
    required DmsFile file,
    required Uint8List bytes,
    String? newFileName,
  }) async {
    final name = (newFileName != null && newFileName.isNotEmpty)
        ? newFileName
        : file.name;
    final storagePath =
        'company_${file.companyId}/dms/${file.folderId ?? "root"}/${DateTime.now().millisecondsSinceEpoch}_$name';
    final stored = await CompanyFileStorage.upload(
      supabaseBucket: 'documents',
      storagePath: storagePath,
      bytes: bytes,
      category: 'dms',
      fileName: name,
    );

    final ext = FileTypeResolver.extensionFromName(name);
    final patch = <String, dynamic>{
      'storage_path': CompanyFileStorage.toStorageReference(stored),
      'storage_provider': stored.provider,
      'external_url': stored.publicOrSignedUrl,
      'file_size': bytes.length,
      'file_size_bytes': bytes.length,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (newFileName != null && newFileName.isNotEmpty) {
      patch['name'] = newFileName;
      if (ext != null) patch['extension'] = ext;
    }

    final row = await DmsService.client
        .from('dms_files')
        .update(patch)
        .eq('id', file.id)
        .select()
        .single();

    return DmsFile.fromJson(row);
  }

  static Future<DmsFile> saveAsNewFile({
    required Uint8List bytes,
    required String fileName,
    required String companyId,
    String? folderId,
  }) async {
    return DmsService.uploadFile(
      bytes: bytes,
      fileName: fileName,
      folderId: folderId,
      companyId: companyId,
    );
  }

  /// Eksporterer ark-data til .xlsx bytes.
  static Uint8List encodeXlsx(Map<String, List<List<String>>> sheets) {
    final book = Excel.createExcel();
    for (final entry in sheets.entries) {
      final sheet = book[entry.key];
      final data = entry.value;
      for (var r = 0; r < data.length; r++) {
        for (var c = 0; c < data[r].length; c++) {
          final v = data[r][c];
          if (v.isEmpty) continue;
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
              .value = TextCellValue(v);
        }
      }
    }
    final encoded = book.encode();
    if (encoded == null) {
      throw StateError('Kunne ikke lagre Excel-fil');
    }
    return Uint8List.fromList(encoded);
  }

  static Map<String, List<List<String>>> decodeXlsx(Uint8List bytes) {
    final book = Excel.decodeBytes(bytes);
    final out = <String, List<List<String>>>{};
    for (final name in book.tables.keys) {
      final table = book.tables[name]!;
      out[name] = table.rows
          .map((row) => row.map((c) => c?.value?.toString() ?? '').toList())
          .toList();
    }
    return out;
  }
}
