import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/dms/dms_file.dart';
import '../../utils/file_type_resolver.dart';
import 'dms_service.dart';

/// Lagre redigerte dokumenter (erstatt eller ny fil).
class DmsFileEditorService {
  DmsFileEditorService._();

  static Future<DmsFile> replaceFile({
    required DmsFile file,
    required Uint8List bytes,
    String? newFileName,
  }) async {
    await DmsService.client.storage.from('documents').uploadBinary(
          file.storagePath,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    final ext = FileTypeResolver.extensionFromName(newFileName ?? file.name);
    final patch = <String, dynamic>{
      'file_size': bytes.length,
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
