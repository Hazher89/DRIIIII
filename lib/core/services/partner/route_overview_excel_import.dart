import 'dart:typed_data';

import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import 'mavi_unit_codes.dart';
import '../../../models/partner/fleet_shift.dart';

class RouteOverviewImportRow {
  final String maviLabel;
  final String normalizedUnitCode;
  final Map<DateTime, String> shiftLabelByDay;
  final Map<DateTime, String?> notesByDay;

  const RouteOverviewImportRow({
    required this.maviLabel,
    required this.normalizedUnitCode,
    required this.shiftLabelByDay,
    this.notesByDay = const {},
  });
}

class RouteOverviewImportResult {
  final List<RouteOverviewImportRow> rows;
  final List<DateTime> days;
  final List<String> warnings;
  final List<String> sheetsParsed;

  const RouteOverviewImportResult({
    required this.rows,
    required this.days,
    required this.warnings,
    required this.sheetsParsed,
  });
}

/// Parser for «Ruteoversikt 2026» — flere UKE-ark, MAVI i kolonne A, dato-serien i rad 3.
class RouteOverviewExcelImport {
  RouteOverviewExcelImport._();

  static final _maviCell = RegExp(r'^M\s*0*(\d{1,5})\b', caseSensitive: false);
  static final _shiftCell = RegExp(r'^([DK])\s*-\s*(.+)$', caseSensitive: false);

  static const _availability = {
    'fri': 'Fri',
    'syk': 'Syk',
    'gitt bort': 'Gitt bort',
    'ledig': 'LEDIG HELE DAG',
  };

  static const _regionAliases = {
    'baerum': 'Bærum',
    'bærum': 'Bærum',
    'ostfold': 'Østfold',
    'østfold': 'Østfold',
    'honefoss': 'Hønefoss',
    'hønefoss': 'Hønefoss',
  };

  static RouteOverviewImportResult parse(Uint8List bytes) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: true);
    final warnings = <String>[];
    final sheetsParsed = <String>[];
    final daySet = <DateTime>{};
    final rowMap = <String, RouteOverviewImportRow>{};

    for (final tableName in decoder.tables.keys) {
      if (!tableName.toUpperCase().startsWith('UKE')) continue;
      final table = decoder.tables[tableName];
      if (table == null) continue;

      final matrix = <List<String>>[];
      for (final row in table.rows) {
        matrix.add(row.map((c) => (c ?? '').toString().trim()).toList());
      }
      if (matrix.length < 4) continue;

      final dateRow = matrix.length > 2 ? matrix[2] : const <String>[];
      final colsDates = <int, DateTime>{};
      for (var c = 0; c < dateRow.length; c++) {
        final d = _tryParseDateCell(dateRow[c]);
        if (d != null) colsDates[c] = d;
      }
      if (colsDates.isEmpty) {
        warnings.add('Ingen datoer i ark $tableName');
        continue;
      }
      sheetsParsed.add(tableName);

      for (var r = 3; r < matrix.length; r++) {
        final line = matrix[r];
        if (line.isEmpty) continue;
        final label = line.first.trim();
        final m = _maviCell.firstMatch(label);
        if (m == null) continue;
        final num = int.tryParse(m.group(1)!);
        if (num == null || num < 1) continue;

        final unit = MaviUnitCodes.normalize('M$num');
        final comment = line.length > 1 ? line[1].trim() : '';
        final existing = rowMap[unit];
        final byDay = Map<DateTime, String>.from(existing?.shiftLabelByDay ?? {});
        final notes = Map<DateTime, String?>.from(existing?.notesByDay ?? {});

        for (final entry in colsDates.entries) {
          if (entry.key >= line.length) continue;
          final cell = line[entry.key].trim();
          if (cell.isEmpty) continue;
          final mapped = _mapCellToShiftName(cell);
          if (mapped == null) {
            warnings.add('${MaviUnitCodes.compactLabel(unit)} ${entry.value.toIso8601String().split('T').first}: ukjent «$cell»');
            continue;
          }
          byDay[entry.value] = mapped;
          daySet.add(entry.value);
          final noteParts = <String>[];
          if (comment.isNotEmpty) noteParts.add(comment);
          if (cell != mapped) noteParts.add(cell);
          if (noteParts.isNotEmpty) {
            notes[entry.value] = noteParts.join(' · ');
          }
        }

        rowMap[unit] = RouteOverviewImportRow(
          maviLabel: MaviUnitCodes.compactLabel(unit),
          normalizedUnitCode: unit,
          shiftLabelByDay: byDay,
          notesByDay: notes,
        );
      }
    }

    final days = daySet.toList()..sort();
    return RouteOverviewImportResult(
      rows: rowMap.values.toList()
        ..sort((a, b) => MaviUnitCodes.compactLabel(a.normalizedUnitCode)
            .compareTo(MaviUnitCodes.compactLabel(b.normalizedUnitCode))),
      days: days,
      warnings: warnings,
      sheetsParsed: sheetsParsed,
    );
  }

  static String? _mapCellToShiftName(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final key = _norm(s);
    if (_availability.containsKey(key)) return _availability[key];
    if (key == 'intern' || key == 'kun kveld' || key == 'kun dag') return null;
    if (key == 'dobbel') return 'Dagrute - Oslo';
    if (key == 'geilo') return 'Dagrute - Hønefoss';

    final m = _shiftCell.firstMatch(s);
    if (m == null) return null;
    final band = m.group(1)!.toUpperCase() == 'D' ? 'Dagrute' : 'Kveldsrute';
    var region = m.group(2)!.trim();
    region = _regionAliases[_norm(region)] ?? region;
    return '$band - $region';
  }

  static DateTime? _tryParseDateCell(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    final serial = double.tryParse(s.replaceAll(',', '.'));
    if (serial != null && serial > 40000 && serial < 60000) {
      final base = DateTime(1899, 12, 30);
      return DateTime(base.year, base.month, base.day + serial.floor());
    }

    final m = RegExp(r'^(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?$').firstMatch(s);
    if (m != null) {
      final day = int.parse(m.group(1)!);
      final month = int.parse(m.group(2)!);
      var year = DateTime.now().year;
      if (m.group(3) != null) {
        year = int.parse(m.group(3)!);
        if (year < 100) year += 2000;
      }
      return DateTime(year, month, day);
    }

    final iso = DateTime.tryParse(s);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);
    return null;
  }

  static FleetShiftDefinition? matchShift(
    String label,
    List<FleetShiftDefinition> shifts,
  ) {
    final mapped = _mapCellToShiftName(label) ?? label;
    final key = _norm(mapped);
    if (key.isEmpty) return null;

    for (final s in shifts) {
      if (_norm(s.name) == key) return s;
    }
    for (final s in shifts) {
      final n = _norm(s.name);
      if (n.contains(key) || key.contains(n)) return s;
    }
    return null;
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-zæøå0-9]'), '');
}
