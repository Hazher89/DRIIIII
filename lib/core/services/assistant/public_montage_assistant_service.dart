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

  int get liveChunkCount => _liveChunkCount;

  /// Force rebuild (etter admin har lagret ny kunnskap).
  Future<void> reloadKnowledge() async {
    _engine = null;
    PublicChatKnowledgeService.instance.invalidateCache();
    await ensureReady(forceRefresh: true);
  }

  Future<void> ensureReady({bool forceRefresh = false}) async {
    if (!forceRefresh && (_engine != null || _loading)) {
      while (_loading) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      return;
    }
    _loading = true;
    try {
      final live = await PublicChatKnowledgeService.instance.publishedChunks(
        forceRefresh: forceRefresh,
      );
      _liveChunkCount = live.length;
      final chunks = <KnowledgeChunk>[
        ...live,
        ...MontageServicesCorpus.chunks(),
        ...PublicExternalOpsCorpus.chunks(),
      ];
      final engine = KnowledgeAssistantEngine(chunks)..buildIndex();
      _engine = engine;
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
        text:
            'Skriv gjerne hva du lurer på — f.eks. montering, ombooking, tidsvindu eller endring av adresse.',
      );
    }

    final intent = _matchIntent(q);
    final expanded = _expandQuery(q);
    final hits = _rankHits(
      q,
      expanded,
      [
        ...engine.search(expanded, limit: 14),
        ...engine.search(q, limit: 10),
        ..._forcedTagHits(expanded),
        ..._forcedTagHits(q),
      ],
      intentBoostId: intent?.chunkId,
    );

    final local = _composeNatural(q, hits, intent);

    // Gemini først — formulerer naturlig for CCC/butikk.
    if (_geminiAvailable != false) {
      try {
        final gemini = await _askGemini(q, hits, intent);
        if (gemini != null && gemini.trim().isNotEmpty) {
          return KnowledgeAnswer(
            found: hits.isNotEmpty || local.found,
            hits: hits.take(3).toList(),
            text: _sanitizeExternal(gemini.trim()),
          );
        }
      } catch (_) {}
    }

    if (local.found) {
      return KnowledgeAnswer(
        found: true,
        hits: hits.take(3).toList(),
        text: _sanitizeExternal(local.text),
      );
    }

    return const KnowledgeAnswer(
      found: false,
      hits: [],
      text:
          'Jeg er ikke helt sikker på det.\n\n'
          'Prøv å spesifisere produkt (vaskemaskin, komfyr, TV…) eller handling '
          '(ombooking, endre adresse, SA, kansellering, fire personer).',
    );
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
    _PublicIntent? intent,
  ) {
    KnowledgeChunk? primary;
    if (intent != null) {
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
      for (final h in hits.take(4)) {
        if (h.chunk.source == KnowledgeSourceKind.liveTrain &&
            h.score >= (hits.first.score - 80)) {
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

    if (primary.source == KnowledgeSourceKind.publicOps) {
      buf.writeln(_rewriteOpsAnswer(primary, intent?.label));
    } else {
      buf.writeln(_rewriteMontageAnswer(primary, q));
    }

    final related = hits
        .where((h) => h.chunk.id != primary!.id)
        .take(2)
        .toList();
    if (related.isNotEmpty) {
      buf.writeln();
      buf.writeln('Du kan også spørre om:');
      for (final h in related) {
        buf.writeln('• ${h.chunk.title}');
      }
    }

    return KnowledgeAnswer(
      found: true,
      hits: hits.take(3).toList(),
      text: buf.toString().trim(),
    );
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
    _PublicIntent? intent,
  ) async {
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
            'body': () {
              final clean = AssistantTextUtils.cleanBody(h.chunk.body);
              return clean.length > 1600 ? clean.substring(0, 1600) : clean;
            }(),
          },
    ];

    if (contexts.isEmpty) {
      contexts.add({
        'title': 'Oversikt',
        'source': 'Levering & montering',
        'body': PublicExternalOpsCorpus.chunks().first.body,
      });
    }

    // Always include compact ops overview for policy grounding.
    contexts.insert(0, {
      'title': 'Retningslinjer for svar',
      'source': 'Policy',
      'body':
          'Målgruppe: CCC og butikk (Elkjøp). Snakk direkte til dem som operatører. '
          'Bruk «du/dere» om handlinger de skal gjøre selv (ombook, sett opp SA, endre i ordren). '
          'ALDRI si «kontakt CCC», «kontakt butikken» eller «ta kontakt med Elkjøp» — de ER CCC/butikk. '
          'Ikke lim inn FAQ ordrett. Formuler naturlig og intelligent. '
          'Aldri nevn interne MAVI-systemer, filer eller hub-rutiner. '
          '${intent != null ? 'Tema: ${intent.label}.' : ''}',
    });

    try {
      final res = await SupabaseService.client.functions.invoke(
        'public-montage-assistant',
        body: {
          'question': question,
          'contexts': contexts.take(10).toList(),
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
