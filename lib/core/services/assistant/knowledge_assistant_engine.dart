import 'assistant_corpus.dart';
import 'assistant_text_utils.dart';

class KnowledgeHit {
  const KnowledgeHit({
    required this.chunk,
    required this.score,
    required this.snippet,
  });

  final KnowledgeChunk chunk;
  final double score;
  final String snippet;
}

class KnowledgeAnswer {
  const KnowledgeAnswer({
    required this.text,
    required this.hits,
    required this.found,
  });

  final String text;
  final List<KnowledgeHit> hits;
  final bool found;
}

/// Gratis søkemotor over DriftPro-kunnskap (uten betalt AI-API).
class KnowledgeAssistantEngine {
  KnowledgeAssistantEngine(this._chunks);

  final List<KnowledgeChunk> _chunks;
  final Map<String, List<String>> _termIndex = {};

  static const _stopWords = {
    'og', 'i', 'på', 'av', 'til', 'for', 'med', 'en', 'et', 'den', 'det', 'de',
    'som', 'er', 'skal', 'kan', 'har', 'var', 'være', 'fra', 'om', 'når', 'hva',
    'hvordan', 'hvor', 'hvem', 'man', 'jeg', 'vi', 'du', 'meg', 'min', 'mitt',
    'the', 'and', 'or', 'in', 'at', 'to', 'of', 'a', 'an', 'is', 'are',
    'how', 'what', 'do', 'does', 'be', 'gjør', 'gjore', 'si', 'fortell',
  };

  static const _concepts = <String, List<String>>{
    'bilutleie': [
      'bilutleie', 'utleie', 'leiebil', 'leieavtale', 'låne bil', 'lånebil',
      'vehicle rental', 'utlevering', 'retur bil',
    ],
    'passord': ['passord', 'password', 'bytt passord', 'innlogging', '000000'],
    'fravaer': [
      'fravær', 'ferie', 'egenmelding', 'sykmelding', 'permisjon', 'sykt barn',
    ],
    'hms': ['hms', 'avvik', 'sja', 'vernerunde', 'risiko', 'kompetanse'],
    'avvik': [
      'avvik', 'registrere', 'registere', 'melde', 'melding', 'deviation',
      'meld avvik', 'nytt avvik', 'kritisk',
    ],
    'ferie': ['ferie', 'fravær', 'fravaer', 'egenmelding', 'permisjon', 'sykmelding'],
    'partner': ['partner', 'rute', 'sjåfør', 'brreg', 'sap', 'sms'],
    'undelivered': [
      'undelivered', 'ulevert', 'uleverte', 'ikke levert', 'kolli',
    ],
    'scanning': ['scan', 'scannes', 'skann', 'scanning', 'scannet'],
    'retur': ['retur', 'returer', 'return', 'reception'],
    'hubanero': ['hubanero', 'check-in', 'check-out', 'lossing', 'mottak'],
    'goran': ['goran', 'lasteliste', 'lasting', 'sjåfør', 'driver'],
    'pris': ['pris', 'gebyr', 'kostnad', 'faktura', '1000', 'drivstoff'],
    'godkjenning': ['godkjenning', 'godkjenn', 'jassy', 'herish', 'julie', 'karwan'],
    'support': ['support', 'hjelp', 'kontakt', 'e-post', 'epost'],
  };

  void buildIndex() {
    _termIndex.clear();
    for (final chunk in _chunks) {
      for (final term in _tokenize(chunk.searchableText)) {
        _termIndex.putIfAbsent(term, () => []).add(chunk.id);
      }
      for (final tag in chunk.tags) {
        for (final term in _tokenize(tag)) {
          _termIndex.putIfAbsent(term, () => []).add(chunk.id);
        }
      }
    }
  }

  KnowledgeAnswer answer(String query, {int limit = 4}) {
    final hits = search(query, limit: limit);
    if (hits.isEmpty || hits.first.score < 12) {
      return const KnowledgeAnswer(
        found: false,
        hits: [],
        text:
            'Jeg fant ikke dette i DriftPro-opplæringen ennå. '
            'Prøv å omformulere (f.eks. «Hvordan melder jeg avvik?»), '
            'eller kontakt hazher@mavilogistikk.no.',
      );
    }

    final top = hits.take(3).toList();
    final primary = top.first;
    final text = _composeAnswer(primary, top.skip(1).toList());

    return KnowledgeAnswer(
      found: true,
      hits: top,
      text: text,
    );
  }

  String _composeAnswer(KnowledgeHit primary, List<KnowledgeHit> related) {
    final body = primary.chunk.body.trim();
    if (body.isEmpty) {
      return 'Se «${primary.chunk.title}» i ${primary.chunk.sourceLabel}.';
    }

    // Steg-for-steg guider: vis innholdet direkte uten «Ifølge …».
    if (RegExp(r'(^|\n)\s*\d+\.\s').hasMatch(body)) {
      final buf = StringBuffer();
      if (primary.chunk.id.contains('avvik')) {
        buf.writeln('Slik registrerer du avvik i DriftPro:');
      } else if (body.length > 900) {
        buf.writeln('${primary.chunk.title}:');
      }
      buf.write(_clip(body, 1200));
      return buf.toString().trim();
    }

    final buf = StringBuffer(_clip(body, 900));
    final extras = related
        .where((h) => h.chunk.id != primary.chunk.id)
        .where(
          (h) =>
              !AssistantTextUtils.looksLikeHtml(h.chunk.title) &&
              h.chunk.title.trim().isNotEmpty,
        )
        .take(2)
        .toList();
    if (extras.isNotEmpty) {
      buf.writeln();
      buf.writeln();
      buf.writeln('Se også:');
      for (final h in extras) {
        buf.writeln('• ${h.chunk.title}');
      }
    }
    return buf.toString().trim();
  }

  List<KnowledgeHit> search(String query, {int limit = 12}) {
    final raw = query.trim();
    if (raw.isEmpty) return const [];

    final expanded = _expandQuery(raw);
    final scores = <String, double>{};
    final qNorm = _normalize(raw);
    final byId = {for (final c in _chunks) c.id: c};

    for (final chunk in _chunks) {
      var score = 0.0;
      final hay = _normalize(chunk.searchableText);

      if (hay.contains(qNorm) && qNorm.length >= 4) {
        score += 80;
      }

      for (final term in expanded) {
        if (term.length < 2) continue;
        if (hay.contains(term)) {
          score += term.length >= 6 ? 18 : 12;
        }
        for (final id in _termIndex[term] ?? const []) {
          if (id == chunk.id) score += 8;
        }
      }

      final queryConcepts = _conceptsForTerms(expanded);
      final entryConcepts = _conceptsForTerms(_tokenize(chunk.searchableText));
      score += queryConcepts.intersection(entryConcepts).length * 24;

      score += _intentBoost(raw, chunk);

      if (score > 0) scores[chunk.id] = score;
    }

    final hits = scores.entries
        .map((e) {
          final chunk = byId[e.key]!;
          return KnowledgeHit(
            chunk: chunk,
            score: e.value,
            snippet: _snippet(chunk, expanded, raw),
          );
        })
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    if (hits.length > limit) return hits.sublist(0, limit);
    return hits;
  }

  double _intentBoost(String query, KnowledgeChunk chunk) {
    final q = _normalize(query);
    final hay = _normalize(chunk.searchableText);
    var boost = 0.0;

    final asksRental = q.contains('bilutleie') ||
        q.contains('leiebil') ||
        q.contains('leieavtale') ||
        q.contains('lane bil') ||
        q.contains('låne bil') ||
        q.contains('lane ut') ||
        q.contains('låne ut') ||
        (q.contains('utleie') &&
            (q.contains('bil') || q.contains('kjoretoy') || q.contains('kjøretøy'))) ||
        (q.contains('leie') &&
            (q.contains('bil') || q.contains('kjoretoy') || q.contains('kjøretøy'))) ||
        ((q.contains('lane') || q.contains('låne')) && q.contains('bil'));

    if (asksRental) {
      if (chunk.source == KnowledgeSourceKind.rental) {
        boost += 80;
      } else {
        boost -= 40;
      }
    }

    final asksRentalPrice = asksRental &&
        (q.contains('pris') ||
            q.contains('koster') ||
            q.contains('gebyr') ||
            (q.contains('dag') && q.contains('bil')));
    if (asksRentalPrice) {
      if (chunk.id == 'rental:price') boost += 200;
      if (chunk.source == KnowledgeSourceKind.rental) boost += 40;
      if (chunk.id.contains('fravaer') || chunk.id.contains('ferie')) boost -= 80;
    }

    final asksWho = q.contains('hvem') ||
        q.contains('kan lane') ||
        q.contains('kan låne') ||
        q.contains('godkjenn') ||
        q.contains('signerer');
    if (asksWho &&
        (asksRental || q.contains('bil')) &&
        (chunk.id == 'rental:approvers' ||
            hay.contains('jassy') ||
            hay.contains('godkjenningsrekkefolge') ||
            hay.contains('godkjenningsrekkefølge'))) {
      boost += 140;
    }

    if ((q.contains('pris') || q.contains('koster') || q.contains('gebyr')) &&
        chunk.source == KnowledgeSourceKind.rental) {
      if (chunk.id == 'rental:price' ||
          hay.contains('1000') ||
          hay.contains('1.000') ||
          hay.contains('pris')) {
        boost += chunk.id == 'rental:price' ? 120 : 60;
      }
    }

    if ((q.contains('avvik') ||
            q.contains('registrer') ||
            q.contains('melde avvik')) &&
        (chunk.id.contains('avvik') || hay.contains('meld nytt avvik'))) {
      boost += chunk.id.contains('avvik') ? 160 : 80;
    }
    if ((q.contains('avvik') || q.contains('registrer')) &&
        chunk.id == 'help:hms') {
      boost -= 50;
    }
    if ((q.contains('ferie') || q.contains('fravær') || q.contains('fravaer')) &&
        chunk.id.contains('fravaer')) {
      boost += 120;
    }
    if (q.contains('hvordan') &&
        chunk.source == KnowledgeSourceKind.sop &&
        chunk.id.startsWith('sop:') &&
        !chunk.id.contains('_err')) {
      boost += 20;
    }

    if ((q.contains('passord') || q.contains('logg inn') || q.contains('innlogging')) &&
        hay.contains('passord')) {
      boost += 50;
    }
    if ((q.contains('godkjenn') ||
            q.contains('hvem signerer') ||
            q.contains('hvem godkjenner')) &&
        (hay.contains('jassy') ||
            hay.contains('godkjenningsrekkefolge') ||
            hay.contains('godkjenningsrekkefølge'))) {
      boost += 50;
    }
    if ((q.contains('undelivered') || q.contains('ulevert')) &&
        hay.contains('undelivered')) {
      boost += 50;
    }
    if ((q.contains('sjekkliste') || q.contains('retur')) &&
        chunk.source == KnowledgeSourceKind.rental &&
        (hay.contains('retur') || hay.contains('utlevering'))) {
      boost += 40;
    }
    return boost;
  }

  Set<String> _expandQuery(String raw) {
    final terms = _tokenize(raw);
    final out = <String>{...terms};
    for (final term in terms) {
      for (final entry in _concepts.entries) {
        if (entry.value.any((v) => _normalize(v).contains(term) || term.contains(_normalize(v)))) {
          out.add(entry.key);
          out.addAll(entry.value.map(_normalize));
        }
      }
    }
    return out;
  }

  Set<String> _conceptsForTerms(Iterable<String> terms) {
    final found = <String>{};
    final joined = terms.join(' ');
    for (final entry in _concepts.entries) {
      for (final syn in entry.value) {
        final s = _normalize(syn);
        if (terms.contains(s) || joined.contains(s)) {
          found.add(entry.key);
          break;
        }
      }
    }
    return found;
  }

  List<String> _tokenize(String text) {
    return _normalize(text)
        .split(RegExp(r'[^a-z0-9æøå]+'))
        .where((t) => t.length >= 2 && !_stopWords.contains(t))
        .toList();
  }

  String _normalize(String s) => s
      .toLowerCase()
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('á', 'a')
      .trim();

  String _snippet(KnowledgeChunk chunk, Set<String> terms, String raw) {
    final body = chunk.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (body.length <= 160) return body;
    final hay = _normalize(body);
    var best = 0;
    for (final t in terms) {
      final i = hay.indexOf(t);
      if (i >= 0) {
        best = i;
        break;
      }
    }
    final start = (best - 40).clamp(0, body.length);
    final end = (start + 160).clamp(0, body.length);
    var snip = body.substring(start, end);
    if (start > 0) snip = '…$snip';
    if (end < body.length) snip = '$snip…';
    return snip;
  }

  String _clip(String text, int max) {
    final t = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max).trimRight()}…';
  }
}
