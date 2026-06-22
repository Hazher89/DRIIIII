import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

import 'sop_training_models.dart';
import 'sop_training_parser.dart';
import 'sop_training_search.dart';

/// Laster og søker i SOP Hub Driftsrutiner.
class SopTrainingService {
  SopTrainingService._();

  static final SopTrainingService instance = SopTrainingService._();

  static const assetPath = 'assets/hms/sop_hub_driftsrutiner_v4_8.docx';

  SopTrainingDocument? _cached;
  SopTrainingSearchEngine? _search;

  static const suggestedQueries = [
    'Hvordan behandle kolli Undelivered?',
    'Hubanero returer Reception',
    'Morgenrutine plukking',
    'Goran lasting sjåfør',
    'Retur ikke scannet — hva gjør jeg?',
    'Eskalering gods i limbo',
    'FO Search HU mangler',
    'Ventesone scanning',
  ];

  Future<SopTrainingDocument> load({bool force = false}) async {
    if (_cached != null && !force) return _cached!;
    final bytes = await rootBundle.load(assetPath);
    final archive = ZipDecoder().decodeBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    final docFile = archive.files.firstWhere(
      (f) => f.name == 'word/document.xml',
      orElse: () => throw StateError('Mangler word/document.xml i SOP'),
    );
    final xml = utf8.decode(docFile.content as List<int>);
    _cached = SopTrainingParser.parseDocumentXml(xml);
    _search = SopTrainingSearchEngine(_cached!.entries)..buildIndex();
    return _cached!;
  }

  List<SopSearchHit> search(String query, {int limit = 30}) {
    if (_search == null || query.trim().isEmpty) return const [];
    return _search!.search(query, limit: limit);
  }

  List<SopTrainingEntry> relatedEntries(SopTrainingEntry entry, {int limit = 6}) {
    final doc = _cached;
    if (doc == null) return const [];

    final scores = <String, double>{};
    for (final other in doc.entries) {
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

    final byId = {for (final e in doc.entries) e.id: e};
    return scores.entries
        .map((e) => byId[e.key])
        .whereType<SopTrainingEntry>()
        .take(limit)
        .toList();
  }
}
