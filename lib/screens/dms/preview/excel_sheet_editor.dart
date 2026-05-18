import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import '../../../core/services/dms/dms_file_editor_service.dart';

/// Excel-lignende regneark med redigering (Pluto Grid).
class ExcelSheetEditor extends StatefulWidget {
  final Uint8List bytes;
  final bool isXls;
  final ValueChanged<Map<String, List<List<String>>>>? onChanged;

  const ExcelSheetEditor({
    super.key,
    required this.bytes,
    this.isXls = false,
    this.onChanged,
  });

  @override
  State<ExcelSheetEditor> createState() => ExcelSheetEditorState();
}

class ExcelSheetEditorState extends State<ExcelSheetEditor> {
  static const _excelGreen = Color(0xFF217346);
  static const _maxRows = 500;
  static const _maxCols = 50;

  late Map<String, List<List<String>>> _sheets;
  late List<String> _sheetNames;
  int _activeIndex = 0;
  final Map<String, PlutoGridStateManager> _managers = {};

  @override
  void initState() {
    super.initState();
    _sheets = widget.isXls ? _loadXls() : DmsFileEditorService.decodeXlsx(widget.bytes);
    if (_sheets.isEmpty) {
      _sheets = {'Ark1': _emptyGrid(30, 15)};
    }
    _sheetNames = _sheets.keys.toList();
  }

  Map<String, List<List<String>>> exportSheets() {
    final out = <String, List<List<String>>>{};
    for (final name in _sheetNames) {
      final mgr = _managers[name];
      if (mgr != null) {
        out[name] = _gridToMatrix(mgr);
      } else {
        out[name] = _sheets[name] ?? [];
      }
    }
    return out;
  }

  Uint8List exportXlsxBytes() {
    return DmsFileEditorService.encodeXlsx(exportSheets());
  }

  Map<String, List<List<String>>> _loadXls() {
    final decoder = SpreadsheetDecoder.decodeBytes(widget.bytes, update: true);
    final out = <String, List<List<String>>>{};
    for (final name in decoder.tables.keys) {
      final table = decoder.tables[name]!;
      out[name] = table.rows
          .map((r) => r.map((c) => c?.toString() ?? '').toList())
          .toList();
    }
    return out;
  }

  List<List<String>> _emptyGrid(int rows, int cols) {
    return List.generate(rows, (_) => List.filled(cols, ''));
  }

  List<List<String>> _gridToMatrix(PlutoGridStateManager mgr) {
    final rows = <List<String>>[];
    for (final row in mgr.rows) {
      final line = <String>[];
      for (var c = 0; c < mgr.columns.length; c++) {
        final field = mgr.columns[c].field;
        line.add(row.cells[field]?.value?.toString() ?? '');
      }
      rows.add(line);
    }
    return rows;
  }

  void _notifyChanged() {
    widget.onChanged?.call(exportSheets());
  }

  List<PlutoColumn> _buildColumns(int colCount) {
    return List.generate(colCount, (c) {
      return PlutoColumn(
        title: _colLabel(c),
        field: 'c$c',
        type: PlutoColumnType.text(),
        width: 96,
        minWidth: 48,
      );
    });
  }

  List<PlutoRow> _buildRows(List<List<String>> data, int colCount) {
    final rowCount = data.length.clamp(1, _maxRows);
    return List.generate(rowCount, (r) {
      final cells = <String, PlutoCell>{};
      for (var c = 0; c < colCount; c++) {
        final val = c < data[r].length ? data[r][c] : '';
        cells['c$c'] = PlutoCell(value: val);
      }
      return PlutoRow(cells: cells);
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeName = _sheetNames[_activeIndex];
    final data = _sheets[activeName] ?? _emptyGrid(30, 15);
    final colCount = data.fold<int>(0, (m, r) => r.length > m ? r.length : m).clamp(8, _maxCols);

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: _excelGreen,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: const Row(
            children: [
              Icon(Icons.table_chart, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Excel – redigerbar visning',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Expanded(
          child: PlutoGrid(
            key: ValueKey(activeName),
            columns: _buildColumns(colCount),
            rows: _buildRows(data, colCount),
            configuration: PlutoGridConfiguration(
              style: PlutoGridStyleConfig(
                gridBackgroundColor: Colors.white,
                gridBorderColor: const Color(0xFFD4D4D4),
                borderColor: const Color(0xFFD4D4D4),
                activatedColor: const Color(0xFFE8F5E9),
                activatedBorderColor: _excelGreen,
                cellTextStyle: const TextStyle(fontSize: 12, color: Color(0xFF212121)),
                columnTextStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF333333),
                ),
                columnHeight: 22,
                rowHeight: 24,
                oddRowColor: const Color(0xFFFAFAFA),
                evenRowColor: Colors.white,
              ),
              columnSize: const PlutoGridColumnSizeConfig(
                autoSizeMode: PlutoAutoSizeMode.scale,
              ),
            ),
            onLoaded: (e) {
              _managers[activeName] = e.stateManager;
              e.stateManager.setSelectingMode(PlutoGridSelectingMode.cell);
              e.stateManager.addListener(_notifyChanged);
            },
          ),
        ),
        Material(
          color: const Color(0xFFF3F3F3),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_sheetNames.length, (i) {
                final sel = i == _activeIndex;
                return GestureDetector(
                  onTap: () {
                    final mgr = _managers[activeName];
                    if (mgr != null) {
                      _sheets[activeName] = _gridToMatrix(mgr);
                    }
                    setState(() => _activeIndex = i);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(top: 4, left: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? Colors.white : const Color(0xFFE8E8E8),
                      border: Border(
                        top: BorderSide(
                          color: sel ? _excelGreen : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Text(
                      _sheetNames[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                        color: sel ? _excelGreen : Colors.black87,
                      ),
                    ),
                  ),
                );
              }),
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
}
