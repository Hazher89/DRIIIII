import '../../config/supabase_config.dart';
import '../supabase_service.dart';
import 'assistant_corpus.dart';
import 'assistant_text_utils.dart';
import 'knowledge_assistant_engine.dart';
import 'montage_services_corpus.dart';
import 'public_chat_knowledge_service.dart';
import 'public_external_ops_corpus.dart';

/// Offentlig chat (/montering) — montering + levering/booking for eksterne.
/// Kunnskap er omskrevet til hva kunden/butikk/CCC skal gjøre.
/// Aldri dump interne rutiner eller rå dokumentsitater.
class PublicMontageAssistantService {
  PublicMontageAssistantService._();

  static final PublicMontageAssistantService instance =
      PublicMontageAssistantService._();

  KnowledgeAssistantEngine? _engine;
  bool _loading = false;
  /// null = ukjent, false = funksjon mangler/feiler (ikke spør igjen hver gang).
  bool? _geminiAvailable;
  int _liveChunkCount = 0;
  DateTime? _engineBuiltAt;

  int get liveChunkCount => _liveChunkCount;

  /// Test-only: inject engine without network.
  void debugSetEngineForTest(
    KnowledgeAssistantEngine engine, {
    int liveCount = 0,
  }) {
    _engine = engine;
    _engineBuiltAt = DateTime.now();
    _liveChunkCount = liveCount;
    _geminiAvailable = false;
  }

  /// Force rebuild (etter admin har lagret ny kunnskap).
  Future<void> reloadKnowledge() async {
    _engine = null;
    _engineBuiltAt = null;
    PublicChatKnowledgeService.instance.invalidateCache();
    await ensureReady(forceRefresh: true);
  }

  Future<void> ensureReady({bool forceRefresh = false}) async {
    final freshEnough = _engine != null &&
        _engineBuiltAt != null &&
        DateTime.now().difference(_engineBuiltAt!) < const Duration(seconds: 20);
    if (!forceRefresh && freshEnough) return;

    if (_loading) {
      while (_loading) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      if (!forceRefresh &&
          _engine != null &&
          _engineBuiltAt != null &&
          DateTime.now().difference(_engineBuiltAt!) <
              const Duration(seconds: 20)) {
        return;
      }
    }

    _loading = true;
    try {
      final live = await PublicChatKnowledgeService.instance.publishedChunks(
        forceRefresh: forceRefresh || !freshEnough,
      );
      _liveChunkCount = live.length;
      final chunks = <KnowledgeChunk>[
        ...live,
        ...MontageServicesCorpus.chunks(),
        ...PublicExternalOpsCorpus.chunks(),
      ];
      final engine = KnowledgeAssistantEngine(chunks)..buildIndex();
      _engine = engine;
      _engineBuiltAt = DateTime.now();
    } finally {
      _loading = false;
    }
  }

  static const suggestedQueries = [
    'Kan kunden få levering tidligere enn booket dato?',
    'Kunden vil ha levering etter kl. 19 i vinduet — hva gjør vi?',
    'Hvordan endrer vi adresse eller telefon på ordren?',
    'Curbside til deliverysite — hvordan?',
    'Kunden glemte en tjeneste — hvordan fikser vi det?',
    'Det trengs fire personer — hva setter vi opp?',
    'Hvordan kansellerer vi leveringen riktig?',
    'Hva er inkludert ved montering av vaskemaskin?',
    'Er side-by-side enkel eller avansert montering?',
    'Vare ikke hentet fra butikk — kan den leveres likevel?',
  ];

  /// Interne ord/fraser som aldri skal komme ut til eksterne.
  static final _leakPatterns = <RegExp>[
    RegExp(r'\bFO search\b', caseSensitive: false),
    RegExp(r'\bHUB Dash(board)?\b', caseSensitive: false),
    RegExp(r'\badhoc[- ]?fil', caseSensitive: false),
    RegExp(r'\bad-hoc\b', caseSensitive: false),
    RegExp(r'\bGoran\b', caseSensitive: false),
    RegExp(r'\bHubanero\b', caseSensitive: false),
    RegExp(r'\bConnectTeam\b', caseSensitive: false),
    RegExp(r'\bSAP\b'),
    RegExp(r'\bFU\b'),
    RegExp(r'\bWMS\b'),
    RegExp(r'\bMilkrun\b', caseSensitive: false),
    RegExp(r'\bAdib\b', caseSensitive: false),
    RegExp(r'\binternmail\b', caseSensitive: false),
    RegExp(r'\bintern[- ]?mail\b', caseSensitive: false),
    RegExp(r'\bkjøreliste\b', caseSensitive: false),
    RegExp(r'\bplanning and execution block\b', caseSensitive: false),
    RegExp(r'\b1100\s*,?-?', caseSensitive: false),
    RegExp(r'\b1500\s*,?-?', caseSensitive: false),
    RegExp(r'\bMx\b'),
    RegExp(r'print(e|er)? ut FU', caseSensitive: false),
  ];

  static const _synonymMap = <String, List<String>>{
    'wash': [
      'vaskemaskin', 'vaskemaskinen', 'vask', 'vasken', 'laundry', 'installwash',
      'installwashw', 'washw', 'våtrom', 'vatrom',
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
    'rebook': [
      'ombook', 'omboking', 'booke om', 'endre dato', 'ny tid',
    ],
    'cancel': [
      'kanseller', 'kansellere', 'avlys', 'avlyse', 'stopp levering',
    ],
    'curbside': [
      'curbside', 'fortauskant', 'første dør',
    ],
    'deliverysite': [
      'deliverysite', 'anvist plass', 'bære inn',
    ],
  };

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
    final q = query.trim();
    if (q.length < 2) {
      return const KnowledgeAnswer(
        found: false,
        hits: [],
        text:
            'Skriv gjerne hva du lurer på — f.eks. montering, ombooking, tidsvindu eller endring av adresse.',
      );
    }

    try {
      await ensureReady().timeout(const Duration(seconds: 2));
    } catch (_) {}

    List<KnowledgeChunk> liveChunks = const [];
    try {
      liveChunks = await PublicChatKnowledgeService.instance
          .publishedChunks(forceRefresh: false)
          .timeout(const Duration(seconds: 2), onTimeout: () => const []);
    } catch (_) {
      liveChunks = const [];
    }

    final engine = _engine;
    var liveHits = _matchLiveAgainst(q, liveChunks);
    if (liveHits.isEmpty && engine != null) {
      liveHits = _matchLiveKnowledge(q);
    }
    // Always keep full live library available for Gemini grounding.
    final allLiveHits = [
      for (final c in liveChunks)
        KnowledgeHit(
          chunk: c,
          score: 30,
          snippet: c.body.length > 120 ? '${c.body.substring(0, 120)}…' : c.body,
        ),
    ];

    final intent = _matchIntent(q);
    final expanded = _expandQuery(q);
    final codeHits = _forceServiceCodeHits(q);
    final searchHits = <KnowledgeHit>[
      ...liveHits,
      ...codeHits,
      if (engine != null) ...engine.search(expanded, limit: 18),
      if (engine != null) ...engine.search(q, limit: 12),
      ..._forcedTagHits(expanded),
      ..._forcedTagHits(q),
    ];
    final hits = _rankHits(
      q,
      expanded,
      searchHits,
      intentBoostId: intent?.chunkId,
    );

    final local = _composeNatural(
      q,
      hits,
      intent,
      preferLive: liveHits.isNotEmpty,
    );

    // Gemini formulerer naturlig — med hele kunnskapsbasen som bakgrunn.
    if (_geminiAvailable != false) {
      try {
        final geminiHits = <KnowledgeHit>[
          ...liveHits,
          ...hits,
          ...allLiveHits,
          ...codeHits,
        ];
        final gemini = await _askGemini(q, geminiHits, intent, localDraft: local.found ? local.text : null)
            .timeout(const Duration(seconds: 8), onTimeout: () => null);
        if (gemini != null &&
            gemini.trim().isNotEmpty &&
            !_geminiContradictsLive(gemini, liveHits.isNotEmpty ? liveHits : allLiveHits)) {
          return KnowledgeAnswer(
            found: hits.isNotEmpty || liveHits.isNotEmpty || local.found,
            hits: hits.take(4).toList(),
            text: _sanitizeExternal(gemini.trim()),
            followUps: _followUpsFrom(hits, excludeId: hits.isEmpty ? null : hits.first.chunk.id),
          );
        }
      } catch (_) {}
    }

    if (liveHits.isNotEmpty) {
      final liveLocal = _composeNatural(q, liveHits, intent, preferLive: true);
      if (liveLocal.found) {
        return KnowledgeAnswer(
          found: true,
          hits: liveHits.take(3).toList(),
          text: _sanitizeExternal(liveLocal.text),
          followUps: _followUpsFrom(hits, excludeId: liveHits.first.chunk.id),
        );
      }
    }

    if (local.found) {
      return KnowledgeAnswer(
        found: true,
        hits: hits.take(3).toList(),
        text: _sanitizeExternal(local.text),
        followUps: _followUpsFrom(
          hits,
          excludeId: hits.isEmpty ? null : hits.first.chunk.id,
        ),
      );
    }

    return KnowledgeAnswer(
      found: false,
      hits: const [],
      text:
          'Jeg er ikke helt sikker på det.\n\n'
          'Prøv å spesifisere produkt (vaskemaskin, komfyr, TV…) eller handling '
          '(ombooking, endre adresse, SA, kansellering, fire personer).',
      followUps: suggestedQueries.take(3).toList(),
    );
  }

  /// Treffer InstallXxx / servicekoder direkte i spørsmålet.
  List<KnowledgeHit> _forceServiceCodeHits(String query) {
    final q = query.toLowerCase();
    final codes = RegExp(r'install[a-z0-9]+|tvon[a-z]+|turndoor|deliverysite|curbside',
            caseSensitive: false)
        .allMatches(query)
        .map((m) => m.group(0)!.toLowerCase())
        .toSet();
    if (codes.isEmpty &&
        !(q.contains('forskjell') ||
            q.contains('vs') ||
            q.contains('versus') ||
            q.contains('eller'))) {
      return const [];
    }

    final out = <KnowledgeHit>[];
    for (final chunk in [
      ...MontageServicesCorpus.chunks(),
      ...PublicExternalOpsCorpus.chunks(),
    ]) {
      final id = chunk.id.toLowerCase();
      final title = chunk.title.toLowerCase();
      final tags = chunk.tags.map((t) => t.toLowerCase()).join(' ');
      var score = 0.0;
      for (final code in codes) {
        if (id.contains(code) ||
            title.contains(code) ||
            tags.contains(code) ||
            chunk.body.toLowerCase().contains(code)) {
          score += 200;
        }
        // installwash should also boost installwashw comparison docs
        if (code.startsWith('installwash') &&
            (id.contains('wash') || title.contains('wash'))) {
          score += 120;
        }
      }
      if (q.contains('forskjell') &&
          (id.contains('compare') || title.contains('forskjell'))) {
        score += 180;
      }
      if (score < 100) continue;
      out.add(
        KnowledgeHit(
          chunk: chunk,
          score: score,
          snippet: chunk.body.length > 140
              ? '${chunk.body.substring(0, 140)}…'
              : chunk.body,
        ),
      );
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  List<KnowledgeHit> _matchLiveAgainst(
    String query,
    List<KnowledgeChunk> chunks,
  ) {
    final q = query.toLowerCase().trim();
    final qTokens = q
        .split(RegExp(r'[^a-zæøå0-9]+', caseSensitive: false))
        .where((t) => t.length >= 3)
        .toSet();
    final out = <KnowledgeHit>[];
    for (final chunk in chunks) {
      if (chunk.source != KnowledgeSourceKind.liveTrain &&
          !chunk.id.startsWith('live.')) {
        continue;
      }
      final hay = '${chunk.title}\n${chunk.body}'.toLowerCase();
      var score = 0.0;
      for (final t in qTokens) {
        if (hay.contains(t)) score += 28;
      }
      if (q.contains('steng') && hay.contains('steng')) score += 100;
      if ((q.contains('åpning') ||
              q.contains('aapning') ||
              q.contains('åpent') ||
              q.contains('aapent') ||
              q.contains('åpner')) &&
          (hay.contains('steng') ||
              hay.contains('åpning') ||
              hay.contains('17'))) {
        score += 90;
      }
      if ((q.contains('lydplanke') ||
              q.contains('lydplnake') ||
              q.contains('soundbar')) &&
          (hay.contains('lyd') || hay.contains('sound'))) {
        score += 100;
      }
      if (hay.contains(q)) score += 60;
      final titleTokens = chunk.title
          .toLowerCase()
          .split(RegExp(r'[^a-zæøå0-9]+'))
          .where((t) => t.length >= 3);
      for (final t in titleTokens) {
        if (qTokens.contains(t) || q.contains(t)) score += 40;
      }
      if (score < 24) continue;
      out.add(
        KnowledgeHit(
          chunk: chunk,
          score: score,
          snippet: chunk.body.length > 140
              ? '${chunk.body.substring(0, 140)}…'
              : chunk.body,
        ),
      );
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  List<String> _followUpsFrom(
    List<KnowledgeHit> hits, {
    String? excludeId,
  }) {
    final out = <String>[];
    for (final h in hits) {
      if (h.chunk.id == excludeId) continue;
      final t = h.chunk.title.trim();
      if (t.isEmpty || t.length > 72) continue;
      if (out.contains(t)) continue;
      out.add(t);
      if (out.length >= 3) break;
    }
    if (out.length < 3) {
      for (final s in suggestedQueries) {
        if (out.contains(s)) continue;
        out.add(s);
        if (out.length >= 3) break;
      }
    }
    return out;
  }

  /// Direkte treff mot Chat Lab-kunnskap i engine.
  List<KnowledgeHit> _matchLiveKnowledge(String query) {
    final engine = _engine;
    if (engine == null) return const [];
    return _matchLiveAgainst(query, engine.allChunks);
  }

  // Keep for edge cases / future Gemini guards.
  // ignore: unused_element
  bool _geminiContradictsLive(String answer, List<KnowledgeHit> hits) {
    final live = hits
        .where((h) => h.chunk.source == KnowledgeSourceKind.liveTrain)
        .take(3);
    if (live.isEmpty) return false;
    final a = answer.toLowerCase();
    final denies = a.contains('dessverre ikke') ||
        a.contains('har ikke') ||
        a.contains('vet ikke') ||
        a.contains('ikke tilgjengelig') ||
        a.contains('kan variere');
    if (!denies) return false;
    for (final h in live) {
      if (RegExp(r'\d').hasMatch(h.chunk.body) ||
          h.chunk.body.toLowerCase().contains('steng') ||
          h.chunk.body.toLowerCase().contains('monterer ikke')) {
        return true;
      }
    }
    return false;
  }

  _PublicIntent? _matchIntent(String query) {
    final q = query.toLowerCase();

    bool any(List<String> words) => words.any(q.contains);

    if (any(['skanne inn', 'skann inn', 'innskann', 'så vi kan booke'])) {
      return const _PublicIntent(
        'ext.rebook_scan',
        'omboking før varen er klar',
      );
    }
    if (any(['tidligere', 'første leveringstid', 'levere tidligere', 'raskere levering'])) {
      return const _PublicIntent('ext.earlier', 'tidligere leveringsdato');
    }
    if (any(['etter kl', 'før kl', '17-22', '17–22', 'hele tidsrom', 'spesielt tidspunkt'])) {
      return const _PublicIntent('ext.time_window', 'tidspunkt i vinduet');
    }
    if (any(['blir denne levert', 'kommer den i dag', 'passert', 'forsinket i dag'])) {
      return const _PublicIntent('ext.status_today', 'status i dag');
    }
    if (any(['klage på montering', 'se på montering', 'standalone', ' sett opp en sa', 'sette opp en sa']) ||
        (q.contains('sa ') && q.contains('kunde'))) {
      return const _PublicIntent('ext.montage_followup', 'oppfølging montering');
    }
    if (any(['fire mann', 'fire personer', '4 mann', '4 personer'])) {
      return const _PublicIntent('ext.four_person', 'fire personer');
    }
    if (any(['ekstra tjeneste', 'glemte', 'legge inn tjeneste', 'legge til tjeneste'])) {
      return const _PublicIntent('ext.extra_service', 'ekstra tjeneste');
    }
    if (any(['endre adresse', 'endre telefon', 'kundenavn', 'kundeinformasjon', 'endre kunde'])) {
      return const _PublicIntent('ext.customer_info', 'endre kundedata');
    }
    if (any(['utlevere', 'ikke skannet levert', 'registrert som levert'])) {
      return const _PublicIntent('ext.utlevere', 'leveringsstatus');
    }
    if (any(['curbside', 'deliverysite', 'fortauskant', 'anvist plass'])) {
      return const _PublicIntent('ext.curbside_site', 'curbside/deliverysite');
    }
    if (any(['ikke hentet', 'hentet fra butikk', 'pick & pack', 'pick and pack', 'pick&pack'])) {
      return const _PublicIntent('ext.store_pickup', 'butikk-henting');
    }
    if (any(['kanseller', 'kansellere', 'avlyse', 'ikke utføres', 'stopp leveringen'])) {
      return const _PublicIntent('ext.cancel', 'kansellering');
    }
    if (any(['return store', 'returhenting', 'hent retur'])) {
      return const _PublicIntent('ext.return_pickup', 'returhenting');
    }
    if (any(['portkode', 'ring først', 'beskjed til sjåfør', 'info til sjåfør'])) {
      return const _PublicIntent('ext.notes', 'beskjed på ordre');
    }
    return null;
  }

  List<KnowledgeHit> _forcedTagHits(String query) {
    final q = query.toLowerCase();
    final out = <KnowledgeHit>[];
    final all = [
      ...MontageServicesCorpus.chunks(),
      ...PublicExternalOpsCorpus.chunks(),
    ];
    for (final chunk in all) {
      var force = false;
      for (final tag in chunk.tags) {
        if (tag.length >= 3 && q.contains(tag.toLowerCase())) force = true;
      }
      for (final entry in _synonymMap.entries) {
        final matchesService = chunk.id.contains(entry.key) ||
            chunk.tags.any((t) => t.contains(entry.key));
        if (!matchesService) continue;
        for (final syn in entry.value) {
          if (q.contains(syn.toLowerCase())) {
            force = true;
            break;
          }
        }
      }
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

  List<KnowledgeHit> _rankHits(
    String original,
    String expanded,
    List<KnowledgeHit> hits, {
    String? intentBoostId,
  }) {
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
      if (intentBoostId != null && id == intentBoostId) bonus += 320;
      if (h.chunk.source == KnowledgeSourceKind.liveTrain) bonus += 220;
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

  KnowledgeAnswer _composeNatural(
    String query,
    List<KnowledgeHit> hits,
    _PublicIntent? intent, {
    bool preferLive = false,
  }) {
    KnowledgeChunk? primary;
    if (preferLive) {
      for (final h in hits) {
        if (h.chunk.source == KnowledgeSourceKind.liveTrain) {
          primary = h.chunk;
          break;
        }
      }
    }
    if (primary == null && intent != null) {
      for (final h in hits) {
        if (h.chunk.id == intent.chunkId) {
          primary = h.chunk;
          break;
        }
      }
      primary ??= () {
        for (final c in PublicExternalOpsCorpus.chunks()) {
          if (c.id == intent.chunkId) return c;
        }
        return null;
      }();
    }
    if (primary == null && hits.isNotEmpty && hits.first.score >= 12) {
      primary = hits.first.chunk;
    }
    // Prefer live-trained knowledge when scores are close.
    if (hits.isNotEmpty) {
      for (final h in hits.take(5)) {
        if (h.chunk.source == KnowledgeSourceKind.liveTrain &&
            h.score >= (hits.first.score - 120)) {
          primary = h.chunk;
          break;
        }
      }
    }
    if (primary == null) {
      return const KnowledgeAnswer(found: false, hits: [], text: '');
    }

    final q = query.toLowerCase();
    final buf = StringBuffer();

    if (primary.source == KnowledgeSourceKind.liveTrain) {
      buf.writeln(_rewriteLiveAnswer(primary));
    } else if (primary.source == KnowledgeSourceKind.publicOps) {
      buf.writeln(_rewriteOpsAnswer(primary, intent?.label));
    } else {
      buf.writeln(_rewriteMontageAnswer(primary, q));
    }

    return KnowledgeAnswer(
      found: true,
      hits: hits.take(3).toList(),
      text: buf.toString().trim(),
    );
  }

  /// Profesjonell formulering av Chat Lab-regler / Q&A — uten unødvendig fyll.
  String _rewriteLiveAnswer(KnowledgeChunk chunk) {
    var body = chunk.body.trim();
    body = body.replaceFirst(RegExp(r'^Spørsmål:\s*.+\n+', multiLine: true), '');
    body = body
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\s*KL\s*', caseSensitive: false), ' kl. ')
        .trim();
    if (body.isEmpty) return chunk.title;

    // Allerede en full setning?
    final lower = body.toLowerCase();
    if (body.length > 28 &&
        (body.contains('.') || body.contains('!') || body.contains('?'))) {
      return _capitalizeSentence(body);
    }

    if (lower.contains('steng') && RegExp(r'\d').hasMatch(body)) {
      return _capitalizeSentence(
        body.endsWith('.') ? body : '$body.',
      );
    }
    if (lower.contains('monterer ikke') || lower.startsWith('vi ')) {
      return _capitalizeSentence(body.endsWith('.') ? body : '$body.');
    }

    // Kort faktum → full setning
    if (body.length < 90 && !body.contains('.')) {
      return _capitalizeSentence('$body.');
    }
    return _capitalizeSentence(body);
  }

  String _capitalizeSentence(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return t;
    return '${t[0].toUpperCase()}${t.substring(1)}';
  }

  /// Naturlige svar til CCC/butikk — «du»-form, aldri «kontakt CCC/butikk».
  static const _naturalAnswers = <String, String>{
    'ext.rebook_scan':
        'Omboking kan først skje når varen faktisk er ankommet/returnert og registrert hos leverandør.\n\n'
        'Book ikke om på forskudd mens varen er underveis. Når den er klar: ombook i deres system med ønsket ny tid.',
    'ext.earlier':
        'Utgangspunktet er booket dato i matrisen — særlig hvis varen ikke har ankommet ennå.\n\n'
        'Unntak: flere feilleveranser på leverandørsiden (f.eks. «rakk ikke»). '
        'Da kan dere forespørre tidligere tid, men varen må være klar først. '
        'Force-tid bare når det er avtalt og varen er klar for levering.',
    'ext.time_window':
        'Levering følger booket tidsvindu (f.eks. 17–22). '
        'Spesifikke klokkeslett inni vinduet — som «først etter 19» — kan ikke loves.\n\n'
        'Hvis kunden ikke kan være hjemme hele vinduet: book om til en dag der hele tidsrommet passer.\n\n'
        'Har det vært flere bomturer på leverandørsiden tidligere, merk det ved ombooking så det kan tas hensyn til.',
    'ext.status_today':
        'Chatten viser ikke live status. Sjekk ordrenummeret i deres egne systemer.\n\n'
        'Ser leveringen ut til å være ute: følg opp slik at kunden får beskjed på vanlig måte.',
    'ext.montage_followup':
        'Sett opp en standalone service (SA) til kunden for ny gjennomgang / oppfølging av monteringen.\n\n'
        'Ved vannlekkasje eller skaderisiko: prioriter — dette kan behandles mer akutt enn vanlig matrise. '
        'Noter kort hva som er galt på ordren/SA.',
    'ext.four_person':
        'Slik håndterer dere fire personer:\n\n'
        '• Allerede levert: opprett SA (f.eks. installfridge / deliveryunp) med ønsket dato.\n'
        '• Ikke levert: book om og merk tydelig at det trengs fire personer + ny tid.\n'
        '• Oppdaget under levering: ekstra mannskap samme dag er ikke alltid mulig — planlegg på nytt.\n\n'
        'Jo tidligere behovet er merket på ordren, jo enklere blir det.',
    'ext.extra_service':
        'Glemt tjeneste — dette kan dere ofte fikse selv:\n\n'
        '• I dag/i morgen + vanlig tjeneste + deliverysite: tjenesten kan ofte legges til under levering '
        '(kunden får betalingslenke etterpå). Avklar før levering.\n'
        '• Lenger frem: legg opp SA på samme dato/tid med samme kundedata.',
    'ext.customer_info':
        'Adresse, telefon og navn endrer dere selv i ordresystemet — leverandør kan ikke gjøre det.\n\n'
        'Som oftest må leveringen bookes om for at endringen skal gjelde.\n\n'
        'Samme dag / i morgen: sørg for at korrekt telefon også følger med til sjåfør, '
        'men den permanente endringen må inn i ordren.',
    'ext.utlevere':
        'Noen ganger er varen levert, men registreringen feiler.\n\n'
        '• Fra i går: vent normalt til neste arbeidsdag — status oppdateres ofte da.\n'
        '• Eldre: følg opp utlevering/status med ordrenummer i deres system / mot leverandør.',
    'ext.curbside_site':
        'Bytt selv fra curbside til deliverysite i ordresystemet før leveringsdagen.\n\n'
        'Leverandør kan ikke endre tjenestetypen for dere.',
    'ext.store_pickup':
        'Hvis varen ikke ble hentet fra butikk, kan den normalt ikke leveres til oppsatt tid.\n\n'
        'Book om med både henting og ny levering, og sørg for at pick & pack er gjort i tide.',
    'ext.cancel':
        'Kanseller ordren selv i Elkjøp-systemet — leverandør kan ikke kansellere for dere.\n\n'
        'Merk/stopp samtidig ordren slik at den ikke blir planlagt for utkjøring.',
    'ext.return_pickup':
        'Returhentingsdato kan ofte justeres.\n\n'
        'Send forespørsel med ordrenummer og ønsket ny dato til planlegging/leverandør.',
    'ext.notes':
        'Legg viktige beskjeder (portkode, ring først, adkomst) direkte på ordren.\n\n'
        '• I dag: sørg for at beskjeden når frem raskt.\n'
        '• I morgen eller senere: legg inn notatet i god tid, så følger det sjåføren.',
  };

  /// Formulerer naturlig svar — aldri rå dokumentsitering.
  String _rewriteOpsAnswer(KnowledgeChunk chunk, String? topic) {
    final polished = _naturalAnswers[chunk.id];
    if (polished != null && polished.trim().isNotEmpty) {
      return polished.trim();
    }

    final paras = chunk.body
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    final buf = StringBuffer();
    for (final p in paras.take(3)) {
      buf.writeln(p);
      buf.writeln();
    }
    return _sanitizeExternal(buf.toString().trim());
  }

  String _rewriteMontageAnswer(KnowledgeChunk chunk, String q) {
    final body = chunk.body;

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

    final name = chunk.title
        .replaceAll(RegExp(r'\s*\(.*?\)\s*'), ' ')
        .replaceAll(RegExp(r'Install[A-Za-z]+/?'), '')
        .trim();

    final buf = StringBuffer();
    buf.writeln(
      name.isEmpty
          ? 'Når dere booker / forklarer denne monteringstjenesten:'
          : 'For $name — dette kan dere bruke mot kunden / i booking:',
    );
    buf.writeln();

    if (wantIncluded) {
      final s = section('Inkludert:');
      if (s.isNotEmpty) {
        buf.writeln('Inkludert:');
        for (final line in s.split('\n')) {
          final t = line.trim();
          if (t.isEmpty) continue;
          buf.writeln(t.startsWith('•') || t.startsWith('-') ? t : '• $t');
        }
        buf.writeln();
      }
    }
    if (wantCustomer || (!wantExcluded && wantIncluded)) {
      final s = section('Kunden sørger for:');
      if (s.isNotEmpty) {
        buf.writeln('Kunden må ha klart:');
        for (final line in s.split('\n')) {
          final t = line.trim();
          if (t.isEmpty) continue;
          buf.writeln(t.startsWith('•') || t.startsWith('-') ? t : '• $t');
        }
        buf.writeln();
      }
    }
    if (wantExcluded || wantIncluded) {
      final s = section('Ikke inkludert:');
      if (s.isNotEmpty) {
        buf.writeln('Ikke inkludert:');
        for (final line in s.split('\n')) {
          final t = line.trim();
          if (t.isEmpty) continue;
          buf.writeln(t.startsWith('•') || t.startsWith('-') ? t : '• $t');
        }
        buf.writeln();
      }
    }

    if (buf.toString().trim().split('\n').length <= 2) {
      final cleaned = body.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
      buf.write(cleaned);
    }

    return buf.toString().trim();
  }

  String _sanitizeExternal(String text) {
    var out = text;
    for (final p in _leakPatterns) {
      out = out.replaceAll(p, '');
    }
    // Aldri «kontakt CCC/butikk» — brukeren ER CCC/butikk.
    out = out.replaceAll(
      RegExp(
        r'[^.!?\n]*\b(kontakt|ta kontakt med|ring|spør)\b[^.!?\n]*\b(CCC|butikk(en)?|Elkj[øo]p CCC)\b[^.!?\n]*[.!?]?',
        caseSensitive: false,
      ),
      '',
    );
    out = out.replaceAll(
      RegExp(r'\bbe\s+(CCC|butikk(en)?)\b', caseSensitive: false),
      'dere kan',
    );
    out = out.replaceAll(
      RegExp(r'\bvia\s+(CCC|butikk)/?(CCC|butikk)?\b', caseSensitive: false),
      'i ordresystemet',
    );
    out = out
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return out;
  }

  Future<String?> _askGemini(
    String question,
    List<KnowledgeHit> hits,
    _PublicIntent? intent, {
    String? localDraft,
  }) async {
    if (!SupabaseConfig.isConfigured || !SupabaseService.isConfigured) {
      return null;
    }

    final seen = <String>{};
    final contexts = <Map<String, String>>[];
    void addHit(KnowledgeHit h) {
      if (!seen.add(h.chunk.id)) return;
      if (!AssistantTextUtils.isUsefulChunk(
        id: h.chunk.id,
        title: h.chunk.title,
        body: h.chunk.body,
      )) {
        return;
      }
      final clean = AssistantTextUtils.cleanBody(h.chunk.body);
      contexts.add({
        'title': AssistantTextUtils.cleanTitle(h.chunk.title),
        'source': h.chunk.sourceLabel,
        'body': clean.length > 1800 ? clean.substring(0, 1800) : clean,
      });
    }

    for (final h in hits.where((h) => h.chunk.source == KnowledgeSourceKind.liveTrain)) {
      addHit(h);
    }
    for (final h in hits.where((h) => h.chunk.source != KnowledgeSourceKind.liveTrain)) {
      addHit(h);
      if (contexts.length >= 14) break;
    }

    // Always ground with montage overview so service-code questions work.
    if (!seen.contains(MontageServicesCorpus.overviewId)) {
      final overview = MontageServicesCorpus.chunks().firstWhere(
        (c) => c.id == MontageServicesCorpus.overviewId,
        orElse: () => MontageServicesCorpus.chunks().first,
      );
      contexts.insert(0, {
        'title': overview.title,
        'source': overview.sourceLabel,
        'body': overview.body.length > 1200
            ? overview.body.substring(0, 1200)
            : overview.body,
      });
    }

    if (contexts.isEmpty) {
      contexts.add({
        'title': 'Oversikt',
        'source': 'Levering & montering',
        'body': PublicExternalOpsCorpus.chunks().first.body,
      });
    }

    contexts.insert(0, {
      'title': 'Retningslinjer for svar',
      'source': 'Policy',
      'body':
          'Målgruppe: CCC og butikk (Elkjøp). Svar som en smart kollega — naturlig, klart og komplett. '
          'Bruk ALL relevant kunnskap under. '
          'Hvis Live trening finnes: det er FASIT. '
          'Ved spørsmål om tjenestekoder (InstallWash, InstallWashW, InstallDish osv.): forklar forskjell/likhet tydelig. '
          'Ikke si at du mangler info som finnes i kunnskapen. '
          'Ikke lim inn FAQ ordrett — formuler som Gemini: profesjonelt og lesbart. '
          'ALDRI «kontakt CCC/butikk». Ingen interne MAVI-systemer. '
          '${intent != null ? 'Tema: ${intent.label}.' : ''}'
          '${localDraft != null && localDraft.isNotEmpty ? ' Utkast du kan forbedre: $localDraft' : ''}',
    });

    try {
      final res = await SupabaseService.client.functions.invoke(
        'public-montage-assistant',
        body: {
          'question': question,
          'contexts': contexts.take(16).toList(),
        },
      );

      final data = res.data;
      if (data is Map && data['error'] != null) {
        final err = '${data['error']}'.toLowerCase();
        if (err.contains('not_found') || err.contains('404')) {
          _geminiAvailable = false;
        }
        return null;
      }
      if (data is Map && data['answer'] is String) {
        _geminiAvailable = true;
        return data['answer'] as String;
      }
      return null;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('404') ||
          msg.contains('not_found') ||
          msg.contains('requested function was not found')) {
        _geminiAvailable = false;
      }
      return null;
    }
  }
}

class _PublicIntent {
  const _PublicIntent(this.chunkId, this.label);
  final String chunkId;
  final String label;
}
