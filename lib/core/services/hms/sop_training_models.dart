/// Modeller for SOP Opplæring (Hub Driftsrutiner).
class SopTrainingDocument {
  const SopTrainingDocument({
    required this.title,
    required this.subtitle,
    required this.documentNumber,
    required this.version,
    required this.entries,
    required this.sections,
    required this.systems,
  });

  final String title;
  final String subtitle;
  final String documentNumber;
  final String version;
  final List<SopTrainingEntry> entries;
  final List<String> sections;
  final List<String> systems;
}

enum SopEntryKind {
  procedure,
  system,
  alert,
  info,
  definition,
  escalation,
  paragraph,
}

class SopTrainingEntry {
  const SopTrainingEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.section,
    required this.subsection,
    required this.kind,
    this.system,
    this.priority,
    this.tags = const [],
    this.relatedColumns = const {},
  });

  final String id;
  final String title;
  final String body;
  final String section;
  final String subsection;
  final SopEntryKind kind;
  final String? system;
  final String? priority;
  final List<String> tags;
  final Map<String, String> relatedColumns;

  /// Ren handlingstekst (uten duplisert tittel / tabell-støy).
  String get answer {
    if (relatedColumns.containsKey('handling')) {
      return relatedColumns['handling']!;
    }
    if (relatedColumns.containsKey('handling ved avvik')) {
      return relatedColumns['handling ved avvik']!;
    }
    if (relatedColumns.containsKey('løsning')) {
      return relatedColumns['løsning']!;
    }
    if (relatedColumns.containsKey('merknad')) {
      return relatedColumns['merknad']!;
    }
    if (body.startsWith('$title — ')) {
      return body.substring(title.length + 3).trim();
    }
    if (body == title) return body;
    return body;
  }

  /// Ekstra søkeord for semantisk matching.
  List<String> get semanticTerms {
    final terms = <String>[...tags];
    if (system != null) terms.add(system!.toLowerCase());
    if (priority != null) terms.add(priority!.toLowerCase());
    for (final c in relatedColumns.values) {
      terms.addAll(c.toLowerCase().split(RegExp(r'\s+')));
    }
    return terms.where((t) => t.length >= 3).toList();
  }

  String get searchableText =>
      '$title $body $answer $section $subsection ${system ?? ''} '
      '${tags.join(' ')} ${relatedColumns.values.join(' ')}';
}

class SopSearchHit {
  const SopSearchHit({
    required this.entry,
    required this.score,
    required this.matchedTerms,
    required this.snippet,
    required this.answer,
    this.confidence = 0,
  });

  final SopTrainingEntry entry;
  final double score;
  final List<String> matchedTerms;
  final String snippet;
  final String answer;
  final double confidence;

  bool get isHighConfidence => confidence >= 0.7;
}
