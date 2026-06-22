import 'sop_training_models.dart';

/// Semantisk søk med norske/engelske synonymer og spørsmålsforståelse.
class SopTrainingSearchEngine {
  SopTrainingSearchEngine(this._entries);

  final List<SopTrainingEntry> _entries;
  final Map<String, List<String>> _termIndex = {};

  static const _stopWords = {
    'og', 'i', 'på', 'av', 'til', 'for', 'med', 'en', 'et', 'den', 'det', 'de',
    'som', 'er', 'skal', 'kan', 'har', 'var', 'være', 'fra', 'om', 'når', 'hva',
    'hvordan', 'hvor', 'hvem', 'man', 'jeg', 'vi', 'du', 'meg', 'min', 'mitt',
    'the', 'and', 'or', 'in', 'at', 'to', 'of', 'a', 'an', 'is', 'are',
    'how', 'what', 'do', 'does', 'be', 'gjør', 'gjore',
  };

  /// Konsept → relaterte søkeord (norsk + engelsk).
  static const _concepts = <String, List<String>>{
    'undelivered': [
      'undelivered', 'ulevert', 'uleverte', 'ikke levert', 'ikke-levert',
      'kolli', 'uleverings', 'ulevering', 'not delivered',
    ],
    'scanning': [
      'scan', 'scannes', 'skann', 'scanning', 'scannet', 'inn i hub',
      'mottatt i hub', 'scan inn',
    ],
    'rebooking': [
      'rebooking', 'rebooke', 'rebook', 'rebooket', 'omplanlegg', 'ccc',
    ],
    'avbestilling': [
      'avbestilling', 'avbestille', 'avbestilt', 'cancellation', 'kansellere',
    ],
    'retur': [
      'retur', 'returer', 'return', 'returnstore', 'reception', 'tilbake',
      'returlabel', 'blueberry',
    ],
    'hubanero': ['hubanero', 'hub anero', 'check-in', 'check-out', 'lossing', 'mottak'],
    'goran': ['goran', 'lasteliste', 'lasting', 'sjåfør', 'sjafor', 'driver'],
    'morgen': ['morgen', 'early morning', 'tidlig', 'plukking', 'picking'],
    'avvik': ['avvik', 'deviation', 'feil', 'eskalér', 'eskalering', 'escalation'],
    'ventesone': ['ventesone', 'waiting area', 'lane', 'venter'],
    'pod': ['pod', 'proof of delivery', 'erp', 'levert i erp'],
    'sap': ['sap', 'sap tm', 'fu', 'hu', 'transportplanlegging'],
    'inventory': ['inventory', 'dashboard', 'hub dashboard', 'lagerstyring'],
    'linehaul': ['line haul', 'linehaul', 'shipment', 'forsendelse', 'linjegods'],
    'gods': ['gods', 'kolli', 'produkt', 'hu', 'paller', 'enheter'],
    'butikk': ['butikk', 'store', 'pick-up', 'henting'],
    'planlegging': ['planlegging', 'planleggingsteam', 'ccc', 'tm'],
  };

  void buildIndex() {
    _termIndex.clear();
    for (final entry in _entries) {
      for (final term in _tokenize(entry.searchableText)) {
        _termIndex.putIfAbsent(term, () => []).add(entry.id);
      }
      for (final term in entry.semanticTerms) {
        _termIndex.putIfAbsent(term, () => []).add(entry.id);
      }
    }
  }

  List<SopSearchHit> search(String query, {int limit = 30}) {
    final raw = query.trim();
    if (raw.isEmpty) return const [];

    final expanded = _expandQuery(raw);
    final scores = <String, double>{};
    final matched = <String, Set<String>>{};
    final qNorm = _normalize(raw);

    for (final entry in _entries) {
      var score = 0.0;
      final hay = _normalize(entry.searchableText);
      final answerHay = _normalize(entry.answer);

      // Full setning / frase
      if (hay.contains(qNorm) || answerHay.contains(qNorm)) {
        score += 80;
        matched.putIfAbsent(entry.id, () => {}).add(raw);
      }

      for (final phrase in _extractPhrases(raw)) {
        final p = _normalize(phrase);
        if (p.length >= 6 && (hay.contains(p) || answerHay.contains(p))) {
          score += 45;
          matched.putIfAbsent(entry.id, () => {}).add(phrase);
        }
      }

      for (final term in expanded) {
        if (term.length < 2) continue;

        if (hay.contains(term) || answerHay.contains(term)) {
          score += term.length >= 6 ? 18 : 12;
          matched.putIfAbsent(entry.id, () => {}).add(term);
        }

        for (final id in _termIndex[term] ?? const []) {
          if (id == entry.id) score += 8;
        }

        // Prefix
        for (final e in _termIndex.entries) {
          if (e.key.length >= 4 &&
              (e.key.startsWith(term) || term.startsWith(e.key)) &&
              e.value.contains(entry.id)) {
            score += 5;
          }
        }
      }

      // Konsept-match: flere konsepter i spørringen som finnes i entry = høyere score
      final queryConcepts = _conceptsForTerms(expanded);
      final entryConcepts = _conceptsForTerms(_tokenize(entry.searchableText));
      final overlap = queryConcepts.intersection(entryConcepts);
      score += overlap.length * 22;

      // Spesialregler for typiske spørsmål
      score += _intentBoost(raw, entry);

      if (entry.priority == 'KRITISK') score += 2;
      if (entry.kind == SopEntryKind.alert) score += 4;

      if (score > 0) scores[entry.id] = score;
    }

    final byId = {for (final e in _entries) e.id: e};
    final hits = scores.entries
        .map((e) {
          final entry = byId[e.key]!;
          return SopSearchHit(
            entry: entry,
            score: e.value,
            matchedTerms: matched[e.key]?.toList() ?? const [],
            snippet: _snippet(entry, expanded, raw),
            answer: entry.answer,
            confidence: _confidence(e.value),
          );
        })
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    if (hits.length > limit) return hits.sublist(0, limit);
    return hits;
  }

  double _intentBoost(String query, SopTrainingEntry entry) {
    final q = _normalize(query);
    final hay = _normalize(entry.searchableText);
    var boost = 0.0;

    // «hvordan behandle kolli undelivered»
    if ((q.contains('undelivered') || q.contains('ulevert')) &&
        (q.contains('behandl') || q.contains('kolli') || q.contains('hva'))) {
      if (hay.contains('undelivered') && hay.contains('scann')) boost += 60;
      if (hay.contains('ulevert') && hay.contains('rebook')) boost += 40;
    }

    if ((q.contains('retur') || q.contains('return')) &&
        (q.contains('hubanero') || q.contains('reception') || q.contains('scan'))) {
      if (hay.contains('retur') && hay.contains('hubanero')) boost += 50;
    }

    if (q.contains('goran') && q.contains('last')) {
      if (hay.contains('goran') && hay.contains('last')) boost += 45;
    }

    if (q.contains('morgen') || q.contains('plukk')) {
      if (hay.contains('plukk') || hay.contains('early morning')) boost += 35;
    }

    if (q.contains('eskal') || q.contains('avvik')) {
      if (entry.kind == SopEntryKind.escalation) boost += 40;
      if (hay.contains('eskal')) boost += 25;
    }

    if (q.contains('ventesone') || q.contains('waiting')) {
      if (hay.contains('ventesone') || hay.contains('waiting')) boost += 40;
    }

    return boost;
  }

  double _confidence(double score) {
    if (score >= 90) return 0.95;
    if (score >= 60) return 0.85;
    if (score >= 40) return 0.7;
    if (score >= 25) return 0.55;
    return 0.35;
  }

  Set<String> _conceptsForTerms(List<String> terms) {
    final out = <String>{};
    for (final concept in _concepts.entries) {
      for (final syn in concept.value) {
        final s = _normalize(syn);
        if (terms.any((t) => t.contains(s) || s.contains(t))) {
          out.add(concept.key);
        }
      }
    }
    return out;
  }

  List<String> _expandQuery(String query) {
    final base = _tokenize(query);
    final expanded = <String>{...base};

    for (final term in base) {
      for (final concept in _concepts.entries) {
        final matches = concept.value.any((s) {
          final n = _normalize(s);
          return n == term || n.contains(term) || term.contains(n);
        });
        if (matches) {
          for (final syn in concept.value) {
            expanded.addAll(_tokenize(syn));
          }
        }
      }
    }

    return expanded.where((t) => !_stopWords.contains(t)).toList();
  }

  List<String> _extractPhrases(String query) {
    final phrases = <String>[query];
    final words = query.split(RegExp(r'\s+'));
    for (var i = 0; i < words.length - 1; i++) {
      phrases.add('${words[i]} ${words[i + 1]}');
      if (i + 2 < words.length) {
        phrases.add('${words[i]} ${words[i + 1]} ${words[i + 2]}');
      }
    }
    return phrases;
  }

  List<String> _tokenize(String text) {
    return _normalize(text)
        .split(RegExp(r'[^a-z0-9æøå]+'))
        .where((w) => w.length >= 2 && !_stopWords.contains(w))
        .toSet()
        .toList();
  }

  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll('æ', 'ae')
      .replaceAll('ø', 'oe')
      .replaceAll('å', 'aa');

  static String _snippet(SopTrainingEntry entry, List<String> terms, String query) {
    final text = entry.answer.isNotEmpty ? entry.answer : entry.body;
    final lower = text.toLowerCase();
    var idx = lower.indexOf(query.toLowerCase());
    if (idx < 0) {
      for (final t in terms) {
        idx = lower.indexOf(t);
        if (idx >= 0) break;
      }
    }
    if (idx < 0) return _truncate(text, 180);
    final start = idx > 50 ? idx - 50 : 0;
    final end = (idx + 130).clamp(0, text.length);
    var snippet = text.substring(start, end).trim();
    if (start > 0) snippet = '…$snippet';
    if (end < text.length) snippet = '$snippet…';
    return snippet;
  }

  static String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max - 1)}…';
  }
}
