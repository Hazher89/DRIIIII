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
      id: 'kom_i_gang',
      title: 'Kom i gang med DriftPro',
      subtitle: 'Navigasjon, innlogging, roller og oversikt',
      assetPath: 'assets/hms/training/guides/driftpro_kom_i_gang.txt',
      kind: TrainingDocKind.plainText,
      tags: [
        'kom i gang',
        'dashboard',
        'innlogging',
        'navigasjon',
        'roller',
        'assistent',
      ],
      iconName: 'apps',
    ),
    TrainingDocMeta(
      id: 'alle_funksjoner',
      title: 'Alle funksjoner (indeks)',
      subtitle: 'Hurtigoversikt over hver modul i DriftPro',
      assetPath: 'assets/hms/training/guides/driftpro_alle_funksjoner.txt',
      kind: TrainingDocKind.plainText,
      tags: [
        'indeks',
        'alle',
        'funksjoner',
        'oversikt',
        'meny',
        'moduler',
      ],
      iconName: 'list_alt',
    ),
    TrainingDocMeta(
      id: 'dashboard',
      title: 'Dashboard',
      subtitle: 'KPI, varsler og hurtighandlinger',
      assetPath: 'assets/hms/training/guides/driftpro_dashboard.txt',
      kind: TrainingDocKind.plainText,
      tags: ['dashboard', 'kpi', 'hurtighandlinger', 'varsler', 'overblikk'],
      iconName: 'dashboard',
    ),
    TrainingDocMeta(
      id: 'undersokelser',
      title: 'Undersøkelser',
      subtitle: 'Svare, opprette og publisere',
      assetPath: 'assets/hms/training/guides/driftpro_undersokelser.txt',
      kind: TrainingDocKind.plainText,
      tags: ['undersøkelser', 'survey', 'publiser', 'spørsmål'],
      iconName: 'poll',
    ),
    TrainingDocMeta(
      id: 'ruter_sjåfor',
      title: 'Dele ut ruter til sjåfører',
      subtitle: 'Tildeling, publisering, AUTO MASS og sjåførportal',
      assetPath: 'assets/hms/training/guides/driftpro_ruter_sjåfor.txt',
      kind: TrainingDocKind.plainText,
      tags: [
        'rute',
        'sjåfør',
        'publiser',
        'tildel',
        'auto mass',
        'pdf',
        'sap',
      ],
      iconName: 'route',
    ),
    TrainingDocMeta(
      id: 'partner_knapper',
      title: 'Knapper i Partnere',
      subtitle: 'Hva fanene og knappene betyr',
      assetPath: 'assets/hms/training/guides/driftpro_partner_knapper.txt',
      kind: TrainingDocKind.plainText,
      tags: [
        'knapper',
        'partnere',
        'faner',
        'publiser',
        'sms',
        'utleie',
        'bilkontroll',
      ],
      iconName: 'touch_app',
    ),
    TrainingDocMeta(
      id: 'partner_portaler',
      title: 'Sjåfør- og eierportal',
      subtitle: 'Partnerportal, bot/trekk og bedriftskort',
      assetPath: 'assets/hms/training/guides/driftpro_partner_portaler.txt',
      kind: TrainingDocKind.plainText,
      tags: [
        'portal',
        'sjåfør',
        'eier',
        'trekk',
        'bot',
        'partner',
      ],
      iconName: 'badge',
    ),
    TrainingDocMeta(
      id: 'fravaer_ferie',
      title: 'Fravær og ferie',
      subtitle: 'Søke, sende og godkjenne — alle faner',
      assetPath: 'assets/hms/training/guides/driftpro_fravaer_ferie.txt',
      kind: TrainingDocKind.plainText,
      tags: [
        'ferie',
        'fravær',
        'godkjenn',
        'søknad',
        'egenmelding',
        'kalender',
        'leder',
        'roster',
      ],
      iconName: 'beach_access',
    ),
    TrainingDocMeta(
      id: 'avvik',
      title: 'Avvik',
      subtitle: 'Melde, følge opp og lukke',
      assetPath: 'assets/hms/training/guides/driftpro_avvik.txt',
      kind: TrainingDocKind.plainText,
      tags: ['avvik', 'hms', 'melde', 'bilder', 'lukke', 'risiko'],
      iconName: 'report',
    ),
    TrainingDocMeta(
      id: 'sja_vernerunde',
      title: 'SJA og vernerunde',
      subtitle: 'Sikker jobbanalyse og vernerunder',
      assetPath: 'assets/hms/training/guides/driftpro_sja_vernerunde.txt',
      kind: TrainingDocKind.plainText,
      tags: ['sja', 'vernerunde', 'ppe', 'sjekkliste', 'hms', 'ros'],
      iconName: 'assignment',
    ),
    TrainingDocMeta(
      id: 'risiko_utstyr_kompetanse',
      title: 'Risiko, utstyr og kompetanse',
      subtitle: 'ROS, risikomatrise, maskiner og kurs',
      assetPath:
          'assets/hms/training/guides/driftpro_risiko_utstyr_kompetanse.txt',
      kind: TrainingDocKind.plainText,
      tags: [
        'risiko',
        'ros',
        'matrise',
        'utstyr',
        'truck',
        'kompetanse',
        'kurs',
        'bevis',
      ],
      iconName: 'grid_view',
    ),
    TrainingDocMeta(
      id: 'dms_dokumenter',
      title: 'Dokumenter (DMS)',
      subtitle: 'Opprette, laste opp og personalmappe',
      assetPath: 'assets/hms/training/guides/driftpro_dms_dokumenter.txt',
      kind: TrainingDocKind.plainText,
      tags: [
        'dms',
        'dokument',
        'personalmappe',
        'opplasting',
        'håndbok',
      ],
      iconName: 'folder',
    ),
    TrainingDocMeta(
      id: 'bilutleie',
      title: 'Bilutleie',
      subtitle: 'Utlevering, godkjenning og retur',
      assetPath: 'assets/hms/training/guides/driftpro_bilutleie.txt',
      kind: TrainingDocKind.plainText,
      tags: [
        'bilutleie',
        'utleie',
        'jassy',
        'retur',
        'bilder',
        'leieavtale',
        'mavi',
      ],
      iconName: 'car_rental',
    ),
    TrainingDocMeta(
      id: 'sms_kunder',
      title: 'SMS til kunder',
      subtitle: 'Kjøreliste / rute-PDF — automatisk kundevarsling',
      assetPath: 'assets/hms/training/guides/driftpro_sms_kunder.txt',
      kind: TrainingDocKind.plainText,
      tags: [
        'sms',
        'kunder',
        'kjøreliste',
        'rute-pdf',
        'varsel',
        'mavi',
      ],
      iconName: 'sms',
    ),
    TrainingDocMeta(
      id: 'bilkontroll',
      title: 'Bilkontroll',
      subtitle: 'EU-kontroll, inspeksjon og utstyr',
      assetPath: 'assets/hms/training/guides/driftpro_bilkontroll.txt',
      kind: TrainingDocKind.plainText,
      tags: [
        'bilkontroll',
        'eu-kontroll',
        'inspeksjon',
        'kjøretøy',
        'service',
      ],
      iconName: 'fact_check',
    ),
    TrainingDocMeta(
      id: 'stempling_detalj',
      title: 'Stempling',
      subtitle: 'Inn/ut, timeliste, min dag og kiosk',
      assetPath: 'assets/hms/training/guides/driftpro_stempling_detalj.txt',
      kind: TrainingDocKind.plainText,
      tags: ['stempling', 'timeliste', 'kiosk', 'inn', 'ut', 'min dag'],
      iconName: 'schedule',
    ),
    TrainingDocMeta(
      id: 'varsler',
      title: 'Varsler',
      subtitle: 'SMS, e-post, audit og innstillinger',
      assetPath: 'assets/hms/training/guides/driftpro_varsler.txt',
      kind: TrainingDocKind.plainText,
      tags: ['varsler', 'sms', 'e-post', 'audit', 'innstillinger'],
      iconName: 'notifications',
    ),
    TrainingDocMeta(
      id: 'mer_admin',
      title: 'Mer-menyen (admin)',
      subtitle: 'Ansatte, tilgang, infoskjerm, assistent m.m.',
      assetPath: 'assets/hms/training/guides/driftpro_mer_admin.txt',
      kind: TrainingDocKind.plainText,
      tags: [
        'mer',
        'ansatte',
        'avdelinger',
        'tilgang',
        'brukergodkjenning',
        'infoskjerm',
        'profil',
      ],
      iconName: 'admin_panel',
    ),
    TrainingDocMeta(
      id: 'stempling_mer',
      title: 'Stempling og Mer (kort)',
      subtitle: 'Kort oversikt — se også egne detaljveiledninger',
      assetPath: 'assets/hms/training/guides/driftpro_stempling_mer.txt',
      kind: TrainingDocKind.plainText,
      tags: [
        'stempling',
        'undersøkelser',
        'profil',
        'tilgang',
        'kiosk',
        'support',
      ],
      iconName: 'more_horiz',
    ),
    TrainingDocMeta(
      id: 'sop_hub',
      title: 'Hub Driftsrutiner',
      subtitle: 'SOP-HUB-001 — hovedopplæring lager/hub',
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
    'Hvordan bruke dashboard?',
    'Hvordan dele ut rute til sjåfør?',
    'Hva betyr Publiser og Tildel?',
    'Hvordan søke ferie?',
    'Hvordan godkjenne fravær?',
    'Hvordan melde avvik?',
    'Hvordan leie ut bil?',
    'SMS til kunder på kjøreliste',
    'Hvordan bruke SJA?',
    'Hvordan kjøre vernerunde?',
    'Hvordan laste opp dokument i DMS?',
    'Bilkontroll og EU-kontroll',
    'Hvordan stemple inn?',
    'Hvordan godkjenne nye brukere?',
    'Risikoanalyse ROS',
    'Kompetansematrise',
    'Waiting area — hva gjør jeg?',
    'Vareoverføring til 1701',
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
              lower.contains('vareoverføring til 1701') ||
              lower.startsWith('hvor') ||
              lower.startsWith('hvordan') ||
              lower.startsWith('når skal') ||
              lower.startsWith('tips') ||
              lower.startsWith('krav ') ||
              lower.startsWith('gode vaner') ||
              lower.startsWith('oversikt') ||
              lower.startsWith('viktige knapper') ||
              lower.startsWith('hovedfaner') ||
              lower.startsWith('sms-relaterte') ||
              lower.startsWith('bilutleie-status') ||
              lower.startsWith('ny bilutleie') ||
              lower.startsWith('godkjenning') ||
              lower.startsWith('retur av bil') ||
              lower.startsWith('pris og regler') ||
              lower.startsWith('søk ferie') ||
              lower.startsWith('mine søknader') ||
              lower.startsWith('godkjenne ferie') ||
              lower.startsWith('sende / melde') ||
              lower.startsWith('behandle avvik') ||
              lower.startsWith('automatisk kunde') ||
              lower.startsWith('sja ') ||
              lower.startsWith('vernerunde') ||
              lower.startsWith('risikoanalyse') ||
              lower.startsWith('opprette') ||
              lower.startsWith('finne dokument') ||
              lower.startsWith('personalmappe') ||
              lower.startsWith('bilkontroll') ||
              lower.startsWith('eu-kontroll') ||
              lower.startsWith('maskiner') ||
              lower.startsWith('stempling') ||
              lower.startsWith('undersøkelser') ||
              lower.startsWith('dashboard') ||
              lower.startsWith('innlogging') ||
              lower.startsWith('driftpro-assistent') ||
              lower.startsWith('opplæring') ||
              lower.startsWith('hvem kan') ||
              lower.startsWith('tildel rute') ||
              lower.startsWith('publiser rute') ||
              lower.startsWith('auto mass') ||
              lower.startsWith('sap ') ||
              lower.startsWith('sjåførportal') ||
              lower.startsWith('flåte'));

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
