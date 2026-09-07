import '../../config/supabase_config.dart';
import '../supabase_service.dart';
import 'assistant_corpus.dart';
import 'assistant_text_utils.dart';
import 'knowledge_assistant_engine.dart';
import 'montage_services_corpus.dart';
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

  static const suggestedQueries = [
    'Hva er inkludert når dere monterer vaskemaskin?',
    'Kan jeg få levering tidligere enn booket dato?',
    'Kan dere komme etter kl. 19 innenfor vinduet?',
    'Hvordan endrer jeg adresse eller telefon?',
    'Kan dere endre fra curbside til deliverysite?',
    'Kunden glemte en tjeneste — hva gjør vi?',
    'Det trengs fire personer for bæring — hva nå?',
    'Kan dere kansellere leveringen for oss?',
    'Hva må jeg gjøre klart før komfyren kommer?',
    'Er side-by-side kjøleskap enkel eller avansert montering?',
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

  Future<void> ensureReady() async {
    if (_engine != null || _loading) {
      while (_loading) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      return;
    }
    _loading = true;
    try {
      final chunks = <KnowledgeChunk>[
        ...MontageServicesCorpus.chunks(),
        ...PublicExternalOpsCorpus.chunks(),
      ];
      final engine = KnowledgeAssistantEngine(chunks)..buildIndex();
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

    // Har vi et skarpt intent-svar, bruk det først (raskt + uten lekkasjer).
    // Gemini er bonus når den er deployet.
    final preferLocal = intent != null &&
        local.found &&
        _naturalAnswers.containsKey(intent.chunkId);

    if (!preferLocal && _geminiAvailable != false) {
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

    if (_geminiAvailable != false) {
      try {
        final gemini = await _askGemini(q, hits, intent);
        if (gemini != null && gemini.trim().isNotEmpty) {
          return KnowledgeAnswer(
            found: hits.isNotEmpty,
            hits: hits.take(3).toList(),
            text: _sanitizeExternal(gemini.trim()),
          );
        }
      } catch (_) {}
    }

    return const KnowledgeAnswer(
      found: false,
      hits: [],
      text:
          'Jeg er ikke helt sikker på det ut fra det jeg har her.\n\n'
          'Prøv å nevne produktet (f.eks. vaskemaskin, komfyr, TV) eller '
          'hva du vil få til (ombooking, endre adresse, ekstra tjeneste, kansellering).\n\n'
          'For booking, pris og ordrestatus: kontakt butikken der kjøpet ble gjort, eller Elkjøp CCC.',
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

  /// Ferdige, naturlige svar — høres ut som AI, ikke som kopiert FAQ.
  static const _naturalAnswers = <String, String>{
    'ext.rebook_scan':
        'Ja — men først må varen faktisk være hos oss (eller returnert og registrert).\n\n'
        'Så lenge den er underveis eller ikke ankommet, kan den ikke bookes om «på forskudd». '
        'Vent til den er klar, og book deretter om via butikk/CCC.\n\n'
        'Tips: Oppgi ordrenummer når du kontakter CCC, så går det fortest.',
    'ext.earlier':
        'Som hovedregel gjelder datoen som allerede er booket i leveringsmatrisen — '
        'særlig hvis varen ikke har ankommet ennå.\n\n'
        'Unntak finnes hvis leveringen har feilet flere ganger på vår side (f.eks. «rakk ikke»). '
        'Da kan CCC spørre om en tidligere tid, men varen må være klar for levering først.\n\n'
        'Beste neste steg: kontakt CCC med ordrenummer og forklar situasjonen.',
    'ext.time_window':
        'Vi planlegger etter det tidsvinduet som er booket — for eksempel 17–22. '
        'Vi kan dessverre ikke love et spesifikt klokkeslett inni vinduet (som «først etter 19»).\n\n'
        'Hvis kunden ikke kan være hjemme hele vinduet, er beste løsning å booke om til en dag '
        'der hele tidsrommet passer.\n\n'
        'Har det vært flere bomturer tidligere som skyldes leveransen, kan CCC be om ekstra hensyn ved ny planlegging.',
    'ext.status_today':
        'Jeg ser ikke live ordrestatus her i chatten.\n\n'
        'Ta kontakt med butikk eller Elkjøp CCC med ordrenummer. '
        'De kan sjekke om leveringen er på vei i dag, og eventuelt sørge for at sjåfør ringer kunden.',
    'ext.montage_followup':
        'Ved klage på montering, eller hvis noe må sjekkes på nytt, ber du CCC sette opp en '
        'standalone service (SA) til kunden.\n\n'
        'Er det vannlekkasje eller fare for skade i hjemmet, si ifra tydelig — da skal det prioriteres raskere enn vanlig.\n\n'
        'Ta med ordrenummer og en kort beskrivelse av problemet.',
    'ext.four_person':
        'Det kommer an på hvor i løpet dere er:\n\n'
        '• Allerede levert hos kunden: Be CCC opprette en SA (f.eks. for bæring/montering) og oppgi ønsket dato.\n'
        '• Ikke levert ennå: Book om leveringen og merk tydelig at det trengs fire personer.\n'
        '• Oppdaget først under levering: Ekstra mannskap samme dag er ikke alltid tilgjengelig. '
        'Ofte må oppdraget fullføres/avbrytes der og da, og ny planlegging skjer via CCC.\n\n'
        'Jo tidligere behovet er merket på ordren, jo enklere blir det.',
    'ext.extra_service':
        'Glemt en tjeneste? Det går ofte fint — avhengig av tidspunkt:\n\n'
        '• Levering i dag/i morgen: Vanlige tjenester kan ofte legges til under levering '
        '(kunden får betalingslenke etterpå). Avklar via CCC/butikk før sjåfør er der.\n'
        '• Lenger frem i tid: CCC kan legge opp en SA på samme dato/tid, så tjenesten følger med.\n\n'
        'Si hvilke tjeneste det gjelder, så blir det riktig fra start.',
    'ext.customer_info':
        'Adresse, telefon og navn endres av butikk/CCC — ikke av oss som leverandør.\n\n'
        'Som oftest må leveringen bookes om for at endringen skal gjelde.\n\n'
        'Er leveringen i dag eller i morgen, kan korrekt telefonnummer noen ganger noteres til sjåfør via CCC, '
        'men den permanente endringen må fortsatt inn i ordren.',
    'ext.utlevere':
        'Noen ganger blir leveringen gjennomført, men registreringen på enheten feiler.\n\n'
        '• Fra i går: Vent normalt til neste arbeidsdag — status oppdateres ofte da.\n'
        '• Eldre leveringer: Kontakt CCC og be dem følge opp utlevering/status i systemet.\n\n'
        'Ha ordrenummer klart.',
    'ext.curbside_site':
        'Bytte fra curbside (fortauskant) til deliverysite (inn til anvist plass) '
        'må gjøres av butikk/CCC i deres system.\n\n'
        'Vi kan ikke endre tjenestetypen fra vår side. Be dem oppdatere ordren før leveringsdagen.',
    'ext.store_pickup':
        'Hvis varen ikke ble hentet fra butikk, kan den normalt ikke leveres til oppsatt tid likevel.\n\n'
        'Ordren må bookes om med både henting og ny levering. '
        'Butikk må også ha gjort pick & pack (klargjort varen) i tide.\n\n'
        'Kontakt butikk/CCC med ordrenummer for å få satt dette riktig.',
    'ext.cancel':
        'Vi kan ikke kansellere ordren i Elkjøps system — det må butikk/CCC gjøre.\n\n'
        'Be dem samtidig bekrefte at leveringen ikke skal kjøres, så den ikke blir planlagt ut.\n\n'
        'Kort sagt: kansellering skjer hos CCC/butikk, ikke hos leverandør.',
    'ext.return_pickup':
        'For returhentinger kan dato ofte justeres ved behov.\n\n'
        'Send forespørsel via CCC med ordrenummer og ønsket ny dato — så ordner de oppfølgingen.',
    'ext.notes':
        'Viktig info til sjåfør (portkode, «ring først», vanskelig adkomst) må ligge på ordren via butikk/CCC.\n\n'
        '• Levering i dag: Be også CCC sørge for at sjåfør får beskjed.\n'
        '• I morgen eller senere: Legg inn notatet i god tid, så følger det automatisk med.',
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
        .where((p) => !p.toLowerCase().startsWith('spørsmål du ofte'))
        .toList();

    final buf = StringBuffer();
    if (topic != null) {
      buf.writeln('Kort fortalt om $topic:');
      buf.writeln();
    }

    for (final p in paras.take(3)) {
      var line = p
          .replaceFirst(RegExp(r'^Svar til ekstern:\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'^Utgangspunkt:\s*', caseSensitive: false), '')
          .trim();
      if (line.toLowerCase().startsWith('vi forklarer')) continue;
      if (line.toLowerCase().startsWith('vi deler ikke')) continue;
      if (line.toLowerCase().startsWith('booking, pris')) {
        buf.writeln();
        buf.writeln(line);
        continue;
      }
      buf.writeln(line);
      buf.writeln();
    }

    buf.writeln(
      'Trenger du endring i ordre, booking eller status: kontakt butikk eller Elkjøp CCC med ordrenummer.',
    );
    return buf.toString().trim();
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
          ? 'Slik fungerer denne monteringstjenesten:'
          : 'For $name hos deg gjelder dette:',
    );
    buf.writeln();

    if (wantIncluded) {
      final s = section('Inkludert:');
      if (s.isNotEmpty) {
        buf.writeln('Det som er inkludert:');
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
        buf.writeln('Det du bør ha klart:');
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
      // Overview / freeform chunk — rewrite lightly
      final cleaned = body
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();
      buf.write(cleaned);
    }

    buf.writeln();
    buf.writeln(
      'Pris og booking avtales via butikken der du handlet — ikke her i chatten.',
    );
    return buf.toString().trim();
  }

  String _sanitizeExternal(String text) {
    var out = text;
    for (final p in _leakPatterns) {
      out = out.replaceAll(p, '');
    }
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
          'Skriv naturlig som en dyktig kundeservice. '
          'Forklar hva kunden/butikk/CCC skal gjøre. '
          'Aldri nevn interne MAVI-systemer, filer, interne mailrutiner, '
          'interne priser for ekstra mannskap, eller hvordan hub jobber. '
          'Ikke lim inn kontekst ordrett — formuler selv. '
          '${intent != null ? 'Brukeren spør om: ${intent.label}.' : ''}',
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
