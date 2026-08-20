import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/office_file_type.dart';
import '../../../core/layout/web_layout.dart';

/// Leser Office-filer direkte i Flutter (uten Google/ekstern viser).
class FlutterOfficePreview extends StatelessWidget {
  final List<int> bytes;
  final String fileName;
  final String? extension;

  const FlutterOfficePreview({
    super.key,
    required this.bytes,
    required this.fileName,
    this.extension,
  });

  static const _maxRows = 400;
  static const _maxCols = 40;

  @override
  Widget build(BuildContext context) {
    final ext = extension?.toLowerCase();
    final type = OfficeFileTypeHelper.fromExtension(ext);

    try {
      switch (type) {
        case OfficeFileType.excel:
          if (ext == 'xls') {
            return _XlsPreview(bytes: bytes);
          }
          return _XlsxPreview(bytes: bytes);
        case OfficeFileType.csv:
          return _CsvPreview(bytes: bytes);
        case OfficeFileType.word:
          return _ZipXmlTextPreview(
            bytes: bytes,
            entryPath: 'word/document.xml',
            title: 'Word-dokument',
          );
        case OfficeFileType.powerpoint:
          return _PptxPreview(bytes: bytes);
        case OfficeFileType.unknown:
          return _tryZipOffice(bytes) ?? _error('Ukjent Office-format');
      }
    } catch (e) {
      return _error('Kunne ikke lese filen: $e');
    }
  }

  Widget? _tryZipOffice(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      if (_findEntry(archive, 'word/document.xml') != null) {
        return _ZipXmlTextPreview(
          bytes: bytes,
          entryPath: 'word/document.xml',
          title: fileName,
        );
      }
      if (_findEntry(archive, 'xl/workbook.xml') != null) {
        return _XlsxPreview(bytes: bytes);
      }
      if (archive.files.any((f) => f.name.startsWith('ppt/slides/'))) {
        return _PptxPreview(bytes: bytes);
      }
    } catch (_) {}
    return null;
  }

  Widget _error(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(msg, textAlign: TextAlign.center),
      ),
    );
  }
}

class _XlsxPreview extends StatelessWidget {
  final List<int> bytes;
  const _XlsxPreview({required this.bytes});

  @override
  Widget build(BuildContext context) {
    final book = Excel.decodeBytes(bytes);
    final names = book.tables.keys.toList();
    if (names.isEmpty) {
      return const Center(child: Text('Tom Excel-fil'));
    }

    return DefaultTabController(
      length: names.length,
      child: Column(
        children: [
          Material(
            color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
            child: TabBar(
              isScrollable: true,
              tabs: names.map((n) => Tab(text: n)).toList(),
            ),
          ),
          Expanded(
            child: DriftProTabView(
              children: names.map((name) {
                final sheet = book.tables[name]!;
                return _ScrollableSheetTable(
                  rows: sheet.rows
                      .map((r) => r.map((c) => c?.value).toList())
                      .toList(),
                  label: 'Excel: $name',
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _XlsPreview extends StatelessWidget {
  final List<int> bytes;
  const _XlsPreview({required this.bytes});

  @override
  Widget build(BuildContext context) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: true);
    final tables = decoder.tables.keys.toList();
    if (tables.isEmpty) {
      return const Center(child: Text('Tom Excel-fil (.xls)'));
    }

    return DefaultTabController(
      length: tables.length,
      child: Column(
        children: [
          Material(
            color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
            child: TabBar(
              isScrollable: true,
              tabs: tables.map((n) => Tab(text: n)).toList(),
            ),
          ),
          Expanded(
            child: DriftProTabView(
              children: tables.map((name) {
                final table = decoder.tables[name]!;
                return _ScrollableSheetTable.fromMatrix(
                  table.rows,
                  label: 'Excel: $name',
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CsvPreview extends StatelessWidget {
  final List<int> bytes;
  const _CsvPreview({required this.bytes});

  @override
  Widget build(BuildContext context) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final lines = const LineSplitter().convert(text);
    final rows = <List<String>>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      rows.add(_parseCsvLine(line));
      if (rows.length > FlutterOfficePreview._maxRows) break;
    }
    return _ScrollableSheetTable.fromMatrix(rows, label: 'CSV');
  }

  List<String> _parseCsvLine(String line) {
    final out = <String>[];
    var cur = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (c == ',' && !inQuotes) {
        out.add(cur.toString());
        cur = StringBuffer();
      } else {
        cur.write(c);
      }
    }
    out.add(cur.toString());
    return out;
  }
}

class _PptxPreview extends StatelessWidget {
  final List<int> bytes;
  const _PptxPreview({required this.bytes});

  @override
  Widget build(BuildContext context) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final slides = archive.files
        .where((f) => f.name.startsWith('ppt/slides/slide') && f.name.endsWith('.xml'))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (slides.isEmpty) {
      return const Center(child: Text('Ingen lysbilder funnet'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: slides.length,
      itemBuilder: (_, i) {
        final xml = utf8.decode(slides[i].content as List<int>);
        final text = _stripXml(xml);
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lysbilde ${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SelectableText(text.isEmpty ? '(tomt)' : text),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ZipXmlTextPreview extends StatelessWidget {
  final List<int> bytes;
  final String entryPath;
  final String title;

  const _ZipXmlTextPreview({
    required this.bytes,
    required this.entryPath,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final file = _findEntry(archive, entryPath);
    if (file == null) {
      return Center(child: Text('Fant ikke $entryPath i arkivet'));
    }
    final text = _stripXml(utf8.decode(file.content as List<int>));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                text.isEmpty ? '(tomt dokument)' : text,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScrollableSheetTable extends StatelessWidget {
  final List<List<dynamic>> rows;
  final String label;

  const _ScrollableSheetTable({
    required this.rows,
    required this.label,
  });

  factory _ScrollableSheetTable.fromMatrix(
    List<List<dynamic>> matrix, {
    required String label,
  }) {
    return _ScrollableSheetTable(rows: matrix, label: label);
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('Tomt ark'));
    }

    final maxCols = rows.fold<int>(
      0,
      (m, r) => r.length > m ? r.length : m,
    );
    final colCount = maxCols.clamp(1, FlutterOfficePreview._maxCols);
    final rowCount = rows.length.clamp(0, FlutterOfficePreview._maxRows);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(
            '$label · viser $rowCount rader × $colCount kolonner',
            style: DriftProTheme.caption,
          ),
        ),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 36,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 48,
                  columns: List.generate(
                    colCount,
                    (c) => DataColumn(
                      label: Text(
                        _colLabel(c),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  rows: List.generate(rowCount, (r) {
                    final row = r < rows.length ? rows[r] : <dynamic>[];
                    return DataRow(
                      cells: List.generate(colCount, (c) {
                        final v = c < row.length ? row[c] : null;
                        return DataCell(
                          Text(
                            _cellText(v),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _colLabel(int i) {
    var s = '';
    var n = i + 1;
    while (n > 0) {
      n--;
      s = String.fromCharCode(65 + (n % 26)) + s;
      n ~/= 26;
    }
    return s;
  }

  static String _cellText(dynamic v) {
    if (v == null) return '';
    if (v is DateTime) {
      return '${v.day.toString().padLeft(2, '0')}.${v.month.toString().padLeft(2, '0')}.${v.year}';
    }
    return v.toString();
  }
}

ArchiveFile? _findEntry(Archive archive, String path) {
  for (final f in archive.files) {
    if (f.name == path) return f;
  }
  return null;
}

String _stripXml(String xml) {
  return xml
      .replaceAll(RegExp(r'<w:tab[^>]*/>', caseSensitive: false), '\t')
      .replaceAll(RegExp(r'</w:p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'&nbsp;'), ' ')
      .replaceAll(RegExp(r'&amp;'), '&')
      .replaceAll(RegExp(r'&lt;'), '<')
      .replaceAll(RegExp(r'&gt;'), '>')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n\s*\n+'), '\n\n')
      .trim();
}
