import 'sop_training_models.dart';

/// Parser for SOP-HUB-001 Word-dokument (OOXML).
class SopTrainingParser {
  static final _wT = RegExp(r'<w:t(?:\s[^>]*)?>([^<]*)</w:t>');
  static final _sectionRe = RegExp(r'^\d+\.\s+');
  static final _subsectionRe = RegExp(r'^\d+\.\d+\s+');
  static final _alertRe = RegExp(r'^[⚠ℹ]\s*(VIKTIG|TIPS|GRUNNREGEL)');
  static final _priorityRe = RegExp(
    r'\b(KRITISK|HØY|MODERAT|LAV)\b',
    caseSensitive: false,
  );

  static SopTrainingDocument parseDocumentXml(String xml) {
    final bodyMatch = RegExp(r'<w:body[^>]*>(.*)</w:body>', dotAll: true).firstMatch(xml);
    if (bodyMatch == null) {
      throw const FormatException('Fant ikke w:body i SOP-dokument');
    }
    final body = bodyMatch.group(1)!;

    final blocks = <_Block>[];
    final blockRe = RegExp(r'<w:(p|tbl)\b[^>]*>.*?</w:\1>', dotAll: true);
    for (final m in blockRe.allMatches(body)) {
      final tag = m.group(1)!;
      final raw = m.group(0)!;
      if (tag == 'p') {
        final text = _extractText(raw);
        if (text.isNotEmpty) blocks.add(_Block.paragraph(text));
      } else {
        blocks.add(_Block.table(_parseTable(raw)));
      }
    }

    var docNumber = 'SOP-HUB-001';
    var version = '';
    var metaParsed = false;
    String section = '';
    String subsection = '';
    final entries = <SopTrainingEntry>[];
    final sectionSet = <String>{};
    final systemSet = <String>{};
    var entryIndex = 0;

    for (final block in blocks) {
      switch (block) {
        case _ParagraphBlock(:final text):
          if (_subsectionRe.hasMatch(text)) {
            subsection = text;
            sectionSet.add(text);
          } else if (_sectionRe.hasMatch(text)) {
            section = text;
            subsection = '';
            sectionSet.add(text);
          } else if (_alertRe.hasMatch(text)) {
            final kind = text.contains('TIPS')
                ? SopEntryKind.info
                : SopEntryKind.alert;
            entries.add(_entry(
              index: entryIndex++,
              title: _alertTitle(text),
              body: text,
              section: section,
              subsection: subsection,
              kind: kind,
              priority: text.contains('KRITISK') ? 'KRITISK' : null,
            ));
          } else if (text.length > 40 && section.isNotEmpty) {
            entries.add(_entry(
              index: entryIndex++,
              title: _truncate(text, 72),
              body: text,
              section: section,
              subsection: subsection,
              kind: SopEntryKind.paragraph,
            ));
          }
        case _TableBlock(:final rows):
          if (rows.isEmpty) continue;
          final header = rows.first.map((c) => c.toLowerCase()).toList();
          final isMeta = !metaParsed && header.contains('dokumentnummer');
          if (isMeta) {
            metaParsed = true;
            for (final row in rows) {
              if (row.length >= 2) {
                final key = row[0].toLowerCase().trim();
                if (key.contains('dokumentnummer')) docNumber = row[1].trim();
                if (key == 'versjon') version = row[1].trim();
              }
            }
            continue;
          }

          final isSystemOverview = header.contains('system') &&
              header.any((h) => h.contains('bruksområde'));
          if (isSystemOverview) {
            for (var i = 1; i < rows.length; i++) {
              final row = rows[i];
              if (row.isEmpty) continue;
              final system = row[0];
              systemSet.add(system);
              entries.add(_entry(
                index: entryIndex++,
                title: system,
                body: row.length > 1 ? row[1] : system,
                section: section.isNotEmpty ? section : '2. Systemoversikt',
                subsection: subsection,
                kind: SopEntryKind.system,
                system: system,
                tags: ['system', system.toLowerCase()],
              ));
            }
            continue;
          }

          for (var i = 1; i < rows.length; i++) {
            final row = rows[i];
            if (row.isEmpty || row.every((c) => c.trim().isEmpty)) continue;

            String title;
            String body;
            String? system;
            String? priority;
            final columns = <String, String>{};

            if (header.length == row.length) {
              for (var c = 0; c < header.length; c++) {
                final key = header[c].trim();
                if (key.isNotEmpty) columns[key] = row[c].trim();
              }
            }

            if (row.length == 1) {
              title = _truncate(row[0], 80);
              body = row[0];
            } else if (header.contains('#') ||
                (header.isNotEmpty && header.first == '#')) {
              title = row.length > 1 ? row[1] : row[0];
              body = title;
              system = _findColumn(row, header, ['system', 'system / ansvarlig']);
              priority = _findColumn(row, header, ['prioritet']);
            } else if (_isSituationTable(header)) {
              title = row[0];
              body = row.length > 1 ? row[1] : row[0];
            } else if (header.first.contains('felt') ||
                header.first.contains('ikon') ||
                header.first.contains('kundebeslutning') ||
                header.first.contains('løsningstype')) {
              title = row[0];
              body = row.length > 1 ? row[1] : row[0];
            } else {
              title = row[0];
              body = row.length > 1 ? row.sublist(1).join('. ') : row[0];
            }

            priority ??= _priorityRe.firstMatch(body)?.group(1)?.toUpperCase();
            system ??= _detectSystem(body);
            if (system != null) systemSet.add(system);

            final kind = header.any((h) => h.contains('eskalering'))
                ? SopEntryKind.escalation
                : header.any((h) => h.contains('betydning') || h.contains('beskrivelse'))
                    ? SopEntryKind.definition
                    : SopEntryKind.procedure;

            entries.add(_entry(
              index: entryIndex++,
              title: title,
              body: body,
              section: section,
              subsection: subsection,
              kind: kind,
              system: system,
              priority: priority,
              columns: columns,
            ));
          }
      }
    }

    return SopTrainingDocument(
      title: 'ELKJØP NORDIC',
      subtitle: 'Hub / Terminal — Driftsrutiner',
      documentNumber: docNumber,
      version: version,
      entries: entries,
      sections: sectionSet.toList(),
      systems: systemSet.toList()..sort(),
    );
  }

  static String _extractText(String xml) {
    return _wT
        .allMatches(xml)
        .map((m) => _decodeXml(m.group(1) ?? ''))
        .join()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<List<String>> _parseTable(String tblXml) {
    final rows = <List<String>>[];
    final rowRe = RegExp(r'<w:tr\b[^>]*>.*?</w:tr>', dotAll: true);
    final cellRe = RegExp(r'<w:tc\b[^>]*>.*?</w:tc>', dotAll: true);

    for (final rowMatch in rowRe.allMatches(tblXml)) {
      final cells = <String>[];
      for (final cellMatch in cellRe.allMatches(rowMatch.group(0)!)) {
        cells.add(_extractText(cellMatch.group(0)!));
      }
      if (cells.isNotEmpty) rows.add(cells);
    }
    return rows;
  }

  static bool _isSituationTable(List<String> header) {
    if (header.isEmpty) return false;
    final h = header.first;
    return h.contains('situasjon') ||
        (h.contains('kontroll') && header.any((c) => c.contains('handling')));
  }

  static String? _findColumn(List<String> row, List<String> header, List<String> keys) {
    for (var i = 0; i < header.length && i < row.length; i++) {
      final h = header[i];
      if (keys.any((k) => h.contains(k))) return row[i];
    }
    return null;
  }

  static String? _detectSystem(String text) {
    const systems = [
      'Hubanero',
      'Goran',
      'FO Search',
      'SAP TM',
      'Inventory Management',
      'Line Haul App',
      'Blueberry',
      'Bluecare',
      'Goods Intake',
    ];
    final lower = text.toLowerCase();
    for (final s in systems) {
      if (lower.contains(s.toLowerCase())) return s;
    }
    return null;
  }

  static String _alertTitle(String text) {
    if (text.contains('VIKTIG')) return 'Viktig';
    if (text.contains('TIPS')) return 'Tips';
    if (text.contains('GRUNNREGEL')) return 'Grunnregel';
    return 'Merknad';
  }

  static String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max - 1)}…';
  }

  static SopTrainingEntry _entry({
    required int index,
    required String title,
    required String body,
    required String section,
    required String subsection,
    required SopEntryKind kind,
    String? system,
    String? priority,
    List<String> tags = const [],
    Map<String, String> columns = const {},
  }) {
    final tagSet = <String>{...tags};
    if (system != null) tagSet.add(system.toLowerCase());
    if (priority != null) tagSet.add(priority.toLowerCase());

    return SopTrainingEntry(
      id: 'sop-$index',
      title: title.trim(),
      body: body.trim(),
      section: section.trim(),
      subsection: subsection.trim(),
      kind: kind,
      system: system,
      priority: priority,
      tags: tagSet.toList(),
      relatedColumns: columns,
    );
  }

  static String _decodeXml(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }
}

sealed class _Block {
  const _Block();
  factory _Block.paragraph(String text) = _ParagraphBlock;
  factory _Block.table(List<List<String>> rows) = _TableBlock;
}

class _ParagraphBlock extends _Block {
  const _ParagraphBlock(this.text);
  final String text;
}

class _TableBlock extends _Block {
  const _TableBlock(this.rows);
  final List<List<String>> rows;
}
