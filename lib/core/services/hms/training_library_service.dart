import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

import 'sop_training_models.dart';
import 'sop_training_parser.dart';
import 'sop_training_search.dart';

/// Metadata for et opplæringsdokument i biblioteket.
class TrainingDocMeta {
  const TrainingDocMeta({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.assetPath,
    required this.kind,
    this.tags = const [],
    this.iconName = 'menu_book',
  });

  final String id;
  final String title;
  final String subtitle;
  final String assetPath;
  final TrainingDocKind kind;
  final List<String> tags;
  final String iconName;
}

enum TrainingDocKind { sopDocx, plainText }

/// Samlet opplæringsbibliotek (SOP Hub + arbeidsinstrukser).
class TrainingLibraryService {
  TrainingLibraryService._();

  static final TrainingLibraryService instance = TrainingLibraryService._();

  static const docs = <TrainingDocMeta>[
    TrainingDocMeta(
      id: 'sop_hub',
      title: 'Hub Driftsrutiner',
      subtitle: 'SOP-HUB-001 — hovedopplæring',
      assetPath: 'assets/hms/sop_hub_driftsrutiner_v4_8.docx',
      kind: TrainingDocKind.sopDocx,
      tags: ['sop', 'hub', 'driftsrutiner', 'hubanero', 'goran'],
      iconName: 'hub',
    ),
    TrainingDocMeta(
      id: 'inventory',
      title: 'Inventory management',
      subtitle: 'Daglige faner og handlinger i HUB Dashboard',
      assetPath: 'assets/hms/training/arbeidsinstruks_inventory.txt',
      kind: TrainingDocKind.plainText,
      tags: [
        'inventory',
        'waiting area',
        'undelivered',
        'pod',
        'return store',
        'ccc',
      ],
      iconName: 'inventory_2',
    ),
    TrainingDocMeta(
      id: 'returmottak',
      title: 'Returmottak',
      subtitle: 'Returskjema, etikett og Hubanero intake',
      assetPath: 'assets/hms/training/arbeidsinstruks_returmottak.txt',
      kind: TrainingDocKind.plainText,
      tags: ['retur', 'returmottak', 'returskjema', 'hubanero', 'goran', 'bilag'],
      iconName: 'assignment_return',
    ),
    TrainingDocMeta(
      id: '1701',
      title: 'Vareoverføring til 1701',
      subtitle: 'Ad-hoc inventory, Excel-rapport og HUB Dash',
      assetPath: 'assets/hms/training/arbeidsinstruks_1701.txt',
      kind: TrainingDocKind.plainText,
      tags: ['1701', 'ad-hoc', 'inventory', 'hubanero', 'pda', 'excel'],
      iconName: 'local_shipping',
    ),
  ];

  static const suggestedQueries = [
    'Hvordan behandle kolli Undelivered?',
    'Waiting area — hva gjør jeg?',
    'Returmottak returskjema',
    'Vareoverføring til 1701',
    'POD in ERP daglig sjekk',
    'Hubanero intake retur',
    'Return store cancellation farger',
    'Ad-hoc inventory Hubanero',
    'Morgenrutine plukking',
    'Goran lasting sjåfør',
  ];

  final Map<String, SopTrainingDocument> _byId = {};
  SopTrainingSearchEngine? _globalSearch;
  bool _loaded = false;

  List<SopTrainingDocument> get allDocs =>
      docs.map((d) => _byId[d.id]).whereType<SopTrainingDocument>().toList();

  SopTrainingDocument? docById(String id) => _byId[id];

  TrainingDocMeta? metaById(String id) {
    for (final d in docs) {
      if (d.id == id) return d;
    }
    return null;
  }

  int get totalEntries =>
      _byId.values.fold(0, (sum, d) => sum + d.entries.length);

  Future<void> loadAll({bool force = false}) async {
    if (_loaded && !force) return;
    _byId.clear();
    for (final meta in docs) {
      try {
        _byId[meta.id] = await _loadOne(meta);
      } catch (e) {
        _byId[meta.id] = SopTrainingDocument(
          title: meta.title,
          subtitle: meta.subtitle,
          documentNumber: meta.id,
          version: '',
          entries: [
            SopTrainingEntry(
              id: '${meta.id}_err',
              title: 'Kunne ikke laste dokument',
              body: e.toString(),
              section: meta.title,
              subsection: '',
              kind: SopEntryKind.info,
              tags: meta.tags,
            ),
          ],
          sections: [meta.title],
          systems: const [],
        );
      }
    }
    final allEntries = <SopTrainingEntry>[
      for (final d in _byId.values) ...d.entries,
    ];
    _globalSearch = SopTrainingSearchEngine(allEntries)..buildIndex();
    _loaded = true;
  }

  Future<SopTrainingDocument> _loadOne(TrainingDocMeta meta) async {
    switch (meta.kind) {
      case TrainingDocKind.sopDocx:
        final bytes = await rootBundle.load(meta.assetPath);
        final archive = ZipDecoder().decodeBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        final docFile = archive.files.firstWhere(
          (f) => f.name == 'word/document.xml',
          orElse: () => throw StateError('Mangler word/document.xml'),
        );
        final xml = utf8.decode(docFile.content as List<int>);
        return SopTrainingParser.parseDocumentXml(xml);
      case TrainingDocKind.plainText:
        final text = await rootBundle.loadString(meta.assetPath);
        return _parsePlainText(meta, text);
    }
  }

  SopTrainingDocument _parsePlainText(TrainingDocMeta meta, String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final entries = <SopTrainingEntry>[];
    final buf = StringBuffer();
    String? currentTitle;
    var idx = 0;

    void flush() {
      final body = buf.toString().trim();
      if (body.isEmpty) return;
      final title = currentTitle ?? _truncate(body, 72);
      entries.add(
        SopTrainingEntry(
          id: '${meta.id}_$idx',
          title: title,
          body: body,
          section: meta.title,
          subsection: currentTitle ?? '',
          kind: SopEntryKind.procedure,
          system: meta.title,
          tags: meta.tags,
        ),
      );
      idx++;
      buf.clear();
    }

    for (final line in lines) {
      final lower = line.toLowerCase();
      final isHeading = line.length < 90 &&
          (RegExp(r'^\d+\.').hasMatch(line) ||
              line.endsWith(':') ||
              (line == line.toUpperCase() &&
                  RegExp(r'[A-ZÆØÅ]').hasMatch(line) &&
                  line.length > 3) ||
              lower.startsWith('arbeidsinstruks') ||
              lower.startsWith('action') ||
              lower.startsWith('waiting area') ||
              lower.startsWith('undelivered') ||
              lower.startsWith('pod ') ||
              lower.startsWith('local dc') ||
              lower.startsWith('return store') ||
              lower.startsWith('typiske farger') ||
              lower.startsWith('andre filtre') ||
              lower.contains('vareoverføring til 1701'));

      if (isHeading && buf.isNotEmpty) {
        flush();
        currentTitle = line.replaceAll(RegExp(r':$'), '');
        buf.writeln(line);
      } else if (isHeading) {
        currentTitle = line.replaceAll(RegExp(r':$'), '');
        buf.writeln(line);
      } else {
        buf.writeln(line);
      }
    }
    flush();

    if (entries.isEmpty) {
      entries.add(
        SopTrainingEntry(
          id: '${meta.id}_0',
          title: meta.title,
          body: text.trim(),
          section: meta.title,
          subsection: '',
          kind: SopEntryKind.procedure,
          system: meta.title,
          tags: meta.tags,
        ),
      );
    }

    return SopTrainingDocument(
      title: meta.title,
      subtitle: meta.subtitle,
      documentNumber: meta.id.toUpperCase(),
      version: '',
      entries: entries,
      sections: entries.map((e) => e.subsection).where((s) => s.isNotEmpty).toSet().toList(),
      systems: [meta.title],
    );
  }

  List<SopSearchHit> search(String query, {String? docId, int limit = 40}) {
    if (query.trim().isEmpty) return const [];
    if (docId != null) {
      final doc = _byId[docId];
      if (doc == null) return const [];
      return (SopTrainingSearchEngine(doc.entries)..buildIndex())
          .search(query, limit: limit);
    }
    return _globalSearch?.search(query, limit: limit) ?? const [];
  }

  List<SopTrainingEntry> relatedEntries(
    SopTrainingEntry entry, {
    int limit = 6,
  }) {
    final scores = <String, double>{};
    final all = <SopTrainingEntry>[
      for (final d in _byId.values) ...d.entries,
    ];
    for (final other in all) {
      if (other.id == entry.id) continue;
      var score = 0.0;
      if (other.section == entry.section && entry.section.isNotEmpty) score += 3;
      if (other.subsection == entry.subsection && entry.subsection.isNotEmpty) {
        score += 4;
      }
      if (other.system != null && other.system == entry.system) score += 5;
      for (final tag in entry.tags) {
        if (other.tags.contains(tag)) score += 2;
      }
      if (score > 0) scores[other.id] = score;
    }
    final byId = {for (final e in all) e.id: e};
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .map((e) => byId[e.key])
        .whereType<SopTrainingEntry>()
        .take(limit)
        .toList();
  }

  static String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max - 1)}…';
  }
}
