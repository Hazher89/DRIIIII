import '../../config/supabase_config.dart';
import '../supabase_service.dart';
import 'assistant_text_utils.dart';
import 'knowledge_assistant_engine.dart';
import 'montage_services_corpus.dart';

/// Offentlig monteringchat — ingen innlogging. Kun PDF-basert tjenestekunnskap.
class PublicMontageAssistantService {
  PublicMontageAssistantService._();

  static final PublicMontageAssistantService instance =
      PublicMontageAssistantService._();

  KnowledgeAssistantEngine? _engine;
  bool _loading = false;

  static const suggestedQueries = [
    'Hva er inkludert når dere monterer vaskemaskin?',
    'Kan dere henge TV på veggen hos meg?',
    'Hva må jeg gjøre klart før komfyren kommer?',
    'Er side-by-side kjøleskap enkel eller avansert montering?',
    'Hva dekker omhengsling av dør?',
    'Hva er forskjellen på enkel og avansert montering?',
  ];

  /// Naturlig språk → tjeneste-stikkord som forbedrer søk.
  static const _synonymMap = <String, List<String>>{
    'wash': [
      'vaskemaskin', 'vaskemaskinen', 'vask', 'vasken', 'laundry', 'installwash',
    ],
    'dryer': [
      'tørketrommel', 'torketrommel', 'tørke', 'trommel', 'installdryer',
    ],
    'cooker': [
      'komfyr', 'komfyren', 'komfyrlevering', 'installcooker',
    ],
    'fridge': [
      'kjøleskap', 'kjoleskap', 'fryser', 'fryseren', 'kjøl', 'installfridge',
      'freezer',
    ],
    'sbs': [
      'sbs', 'side-by-side', 'side by side', 'sidebyside', 'amerikansk kjøleskap',
    ],
    'dish': [
      'oppvask', 'oppvaskmaskin', 'oppvaskmaskinen', 'installdish', 'dishwasher',
    ],
    'hood': [
      'ventilator', 'kjøkkenvifte', 'vifte', 'hood', 'installhood',
    ],
    'micro': [
      'mikro', 'mikrobølge', 'mikrobølgeovn', 'micro', 'installmicro',
    ],
    'hob': [
      'platetopp', 'koketopp', 'induksjon', 'hob', 'installhob',
    ],
    'oven': [
      'ovn', 'ovnen', 'innebygd ovn', 'installoven',
    ],
    'tvwall': [
      'tv på vegg', 'henge tv', 'veggmontering', 'veggfeste', 'tvonwall',
      'opphengt tv', 'feste tv',
    ],
    'tvstand': [
      'tv på fot', 'tv-benk', 'tvonstand', 'tv fot',
    ],
    'turndoor': [
      'omheng', 'omhengsling', 'bytte dørhengsel', 'dørhengsel', 'turndoor',
      'snu dør',
    ],
  };

  Future<void> ensureReady() async {
    if (_engine != null || _loading) {
      while (_loading) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      return;
    }
    _loading = true;
    try {
      final engine = KnowledgeAssistantEngine(MontageServicesCorpus.chunks())
        ..buildIndex();
      _engine = engine;
    } finally {
      _loading = false;
    }
  }

  String _expandQuery(String raw) {
    final q = raw.toLowerCase();
    final extras = <String>{};
    for (final entry in _synonymMap.entries) {
      for (final syn in entry.value) {
        if (q.contains(syn.toLowerCase())) {
          extras.add(entry.key);
          extras.addAll(entry.value.take(3));
          break;
        }
      }
    }
    if (extras.isEmpty) return raw;
    return '$raw ${extras.join(' ')}';
  }

  Future<KnowledgeAnswer> ask(String query) async {
    await ensureReady();
    final engine = _engine;
    if (engine == null) {
      return const KnowledgeAnswer(
        found: false,
        hits: [],
        text: 'Chatten kunne ikke lastes. Prøv igjen.',
      );
    }

    final q = query.trim();
    if (q.length < 2) {
      return const KnowledgeAnswer(
        found: false,
        hits: [],
        text: 'Skriv et spørsmål om monteringstjenestene.',
      );
    }

    final expanded = _expandQuery(q);
    final hits = _rankMontageHits(
      q,
      expanded,
      [
        ...engine.search(expanded, limit: 12),
        ...engine.search(q, limit: 8),
        ..._forcedTagHits(expanded),
        ..._forcedTagHits(q),
      ],
    );
    final local = _composeLocal(q, hits);

    try {
      final gemini = await _askGemini(q, hits);
      if (gemini != null && gemini.trim().isNotEmpty) {
        return KnowledgeAnswer(
          found: hits.isNotEmpty || local.found,
          hits: hits.take(3).toList(),
          text: gemini.trim(),
        );
      }
    } catch (_) {}

    if (local.found) return local;

    return const KnowledgeAnswer(
      found: false,
      hits: [],
      text:
          'Jeg fant ikke nok i tjenesteoversikten til å svare sikkert. '
          'Prøv å nevne produktet (f.eks. vaskemaskin, komfyr, TV, oppvaskmaskin) '
          'og om du lurer på det som er inkludert, det du må gjøre, eller det som ikke er inkludert.\n\n'
          'For booking eller pris: kontakt butikken der du handlet.',
    );
  }

  List<KnowledgeHit> _forcedTagHits(String query) {
    final q = query.toLowerCase();
    final out = <KnowledgeHit>[];
    for (final chunk in MontageServicesCorpus.chunks()) {
      var force = false;
      for (final tag in chunk.tags) {
        if (tag.length >= 3 && q.contains(tag.toLowerCase())) force = true;
      }
      for (final entry in _synonymMap.entries) {
        if (!chunk.id.contains(entry.key) &&
            !chunk.tags.any((t) => t.contains(entry.key))) {
          continue;
        }
        for (final syn in entry.value) {
          if (q.contains(syn.toLowerCase())) {
            force = true;
            break;
          }
        }
      }
      final code =
          RegExp(r'install[a-z]+|tvon[a-z]+|turndoor', caseSensitive: false)
              .firstMatch(chunk.title)
              ?.group(0)
              ?.toLowerCase();
      if (code != null && q.contains(code)) force = true;
      if (q.contains('omheng') && chunk.id.contains('turndoor')) force = true;
      if (!force) continue;
      out.add(
        KnowledgeHit(
          chunk: chunk,
          score: 80,
          snippet: chunk.body.length > 120
              ? '${chunk.body.substring(0, 120)}…'
              : chunk.body,
        ),
      );
    }
    return out;
  }

  List<KnowledgeHit> _rankMontageHits(
    String original,
    String expanded,
    List<KnowledgeHit> hits,
  ) {
    final seen = <String>{};
    final unique = <KnowledgeHit>[];
    for (final h in hits) {
      if (seen.add(h.chunk.id)) unique.add(h);
    }

    final q = expanded.toLowerCase();
    final scored = <({KnowledgeHit hit, double bonus})>[];
    for (final h in unique) {
      var bonus = h.score;
      final title = h.chunk.title.toLowerCase();
      final id = h.chunk.id.toLowerCase();
      for (final tag in h.chunk.tags) {
        final t = tag.toLowerCase();
        if (t.length >= 3 && q.contains(t)) bonus += 120;
      }
      for (final entry in _synonymMap.entries) {
        final matchesService = id.contains(entry.key) ||
            h.chunk.tags.any((t) => t.toLowerCase().contains(entry.key));
        if (!matchesService) continue;
        for (final syn in entry.value) {
          if (original.toLowerCase().contains(syn.toLowerCase()) ||
              q.contains(syn.toLowerCase())) {
            bonus += 180;
            break;
          }
        }
      }
      final code =
          RegExp(r'install[a-z]+|tvon[a-z]+|turndoor', caseSensitive: false)
              .firstMatch(h.chunk.title)
              ?.group(0)
              ?.toLowerCase();
      if (code != null && q.contains(code)) bonus += 160;
      if (q.contains('omheng') &&
          (id.contains('turndoor') || title.contains('omheng'))) {
        bonus += 200;
      }
      if ((q.contains('enkel') || q.contains('sjåfør') || q.contains('sjafor')) &&
          id.contains('simple')) {
        bonus += 40;
      }
      if ((q.contains('avansert') || q.contains('montør') || q.contains('montor')) &&
          id.contains('adv')) {
        bonus += 40;
      }
      scored.add((hit: h, bonus: bonus));
    }
    scored.sort((a, b) => b.bonus.compareTo(a.bonus));
    return [
      for (final s in scored)
        KnowledgeHit(
          chunk: s.hit.chunk,
          score: s.bonus,
          snippet: s.hit.snippet,
        ),
    ];
  }

  KnowledgeAnswer _composeLocal(String query, List<KnowledgeHit> hits) {
    if (hits.isEmpty || hits.first.score < 12) {
      return const KnowledgeAnswer(found: false, hits: [], text: '');
    }
    final primary = hits.first;
    final q = query.toLowerCase();
    final body = primary.chunk.body;

    String section(String header) {
      final idx = body.indexOf(header);
      if (idx < 0) return '';
      final rest = body.substring(idx + header.length);
      final next = [
        rest.indexOf('\nInkludert:'),
        rest.indexOf('\nKunden sørger for:'),
        rest.indexOf('\nIkke inkludert:'),
      ].where((i) => i > 0).fold<int?>(null, (a, b) => a == null ? b : (b < a ? b : a));
      final slice = next == null ? rest : rest.substring(0, next);
      return slice.trim();
    }

    final wantExcluded =
        q.contains('ikke inkludert') || q.contains('dekker ikke') || q.contains('utenom');
    final wantCustomer = q.contains('må jeg') ||
        q.contains('sørge') ||
        q.contains('klart') ||
        q.contains('forberede') ||
        q.contains('kunden');
    final wantIncluded = q.contains('inkludert') ||
        q.contains('gjør dere') ||
        q.contains('hva får') ||
        (!wantExcluded && !wantCustomer);

    final buf = StringBuffer();
    buf.writeln('For **${primary.chunk.title}**:');
    buf.writeln();

    if (wantIncluded) {
      final s = section('Inkludert:');
      if (s.isNotEmpty) {
        buf.writeln('**Inkludert**');
        buf.writeln(s);
        buf.writeln();
      }
    }
    if (wantCustomer) {
      final s = section('Kunden sørger for:');
      if (s.isNotEmpty) {
        buf.writeln('**Du / kunden sørger for**');
        buf.writeln(s);
        buf.writeln();
      }
    }
    if (wantExcluded) {
      final s = section('Ikke inkludert:');
      if (s.isNotEmpty) {
        buf.writeln('**Ikke inkludert**');
        buf.writeln(s);
        buf.writeln();
      }
    }

    // Fallback: full body if sections empty.
    if (buf.toString().trim().split('\n').length <= 2) {
      buf.write(body.trim());
    }

    final related = hits.skip(1).take(2).toList();
    if (related.isNotEmpty) {
      buf.writeln();
      buf.writeln('Relatert:');
      for (final h in related) {
        buf.writeln('• ${h.chunk.title}');
      }
    }

    return KnowledgeAnswer(
      found: true,
      hits: hits.take(3).toList(),
      text: buf.toString().trim().replaceAll('**', ''),
    );
  }

  Future<String?> _askGemini(String question, List<KnowledgeHit> hits) async {
    if (!SupabaseConfig.isConfigured || !SupabaseService.isConfigured) {
      return null;
    }

    final contexts = <Map<String, String>>[
      for (final h in hits)
        if (AssistantTextUtils.isUsefulChunk(
          id: h.chunk.id,
          title: h.chunk.title,
          body: h.chunk.body,
        ))
          {
            'title': AssistantTextUtils.cleanTitle(h.chunk.title),
            'source': h.chunk.sourceLabel,
            'body': AssistantTextUtils.cleanBody(h.chunk.body).length > 1800
                ? AssistantTextUtils.cleanBody(h.chunk.body).substring(0, 1800)
                : AssistantTextUtils.cleanBody(h.chunk.body),
          },
    ];

    if (contexts.isEmpty) {
      final overview = MontageServicesCorpus.chunks().first;
      contexts.add({
        'title': overview.title,
        'source': overview.sourceLabel,
        'body': overview.body,
      });
    }

    final res = await SupabaseService.client.functions.invoke(
      'public-montage-assistant',
      body: {
        'question': question,
        'contexts': contexts,
      },
    );

    final data = res.data;
    if (data is Map && data['error'] != null) return null;
    if (data is Map && data['answer'] is String) {
      return data['answer'] as String;
    }
    return null;
  }
}
