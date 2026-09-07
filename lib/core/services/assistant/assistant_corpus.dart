import 'package:flutter/services.dart' show rootBundle;

import '../../constants/vehicle_rental_agreement.dart';
import '../../hms/iso14000_guide.dart';
import '../../hms/mavi_hms_handbook.dart';
import '../../routing/app_paths.dart';
import '../hms/sop_training_models.dart';
import '../hms/training_library_service.dart';
import '../../../screens/more/driftpro_platform_catalog.dart';
import 'assistant_app_faq.dart';
import 'assistant_leave_intelligence.dart';
import 'assistant_route_intelligence.dart';
import 'assistant_text_utils.dart';
import 'montage_services_corpus.dart';

enum KnowledgeSourceKind {
  sop,
  rental,
  help,
  montage,
  publicOps,
  liveTrain,
  hms,
}

/// Én indekserbar kunnskapsbit for DriftPro-assistenten.
class KnowledgeChunk {
  const KnowledgeChunk({
    required this.id,
    required this.source,
    required this.title,
    required this.body,
    this.routePath,
    this.tags = const [],
  });

  final String id;
  final KnowledgeSourceKind source;
  final String title;
  final String body;
  final String? routePath;
  final List<String> tags;

  String get searchableText => '$title $body ${tags.join(' ')}';

  String get sourceLabel {
    switch (source) {
      case KnowledgeSourceKind.sop:
        return 'SOP / opplæring';
      case KnowledgeSourceKind.rental:
        return 'Bilutleie';
      case KnowledgeSourceKind.help:
        return 'Hjelp & støtte';
      case KnowledgeSourceKind.montage:
        return 'Monteringstjenester';
      case KnowledgeSourceKind.publicOps:
        return 'Levering & booking';
      case KnowledgeSourceKind.liveTrain:
        return 'Live trening';
      case KnowledgeSourceKind.hms:
        return 'HMS-håndbok';
    }
  }
}

/// Bygger kunnskapsindeks fra SOP, HMS, bilutleie og hjelpetekster.
class AssistantCorpus {
  AssistantCorpus._();

  static const _maxChunkChars = 1800;

  static Future<List<KnowledgeChunk>> build() async {
    final chunks = <KnowledgeChunk>[
      ...AssistantAppFaq.chunks(),
      ...AssistantRouteIntelligence.faqHints(),
      ...AssistantLeaveIntelligence.faqHints(),
      ..._rentalChunks(),
      ..._helpChunks(),
      ..._catalogChunks(),
      ..._iso14000Chunks(),
      ...MontageServicesCorpus.chunks(),
    ];

    try {
      await TrainingLibraryService.instance.loadAll();
      for (final doc in TrainingLibraryService.instance.allDocs) {
        chunks.addAll(_sopChunks(doc));
      }
    } catch (_) {
      // Opplæringsassets kan mangle lokalt — resten av corpus fungerer fortsatt.
    }

    try {
      chunks.addAll(await _hmsHandbookChunks());
    } catch (_) {
      // HMS-assets kan mangle i enkelte builds.
    }

    return _sanitize(chunks);
  }

  static Future<List<KnowledgeChunk>> _hmsHandbookChunks() async {
    final out = <KnowledgeChunk>[];
    for (final doc in MaviHmsHandbook.docs) {
      try {
        final raw = await rootBundle.loadString(doc.assetPath);
        final cleaned = AssistantTextUtils.cleanBody(raw);
        if (cleaned.trim().length < 40) continue;
        final pieces = _splitBody(cleaned);
        for (var i = 0; i < pieces.length; i++) {
          final suffix = pieces.length == 1 ? '' : ' (${i + 1}/${pieces.length})';
          out.add(
            KnowledgeChunk(
              id: 'hms:${doc.id}:$i',
              source: KnowledgeSourceKind.hms,
              title: '${doc.title}$suffix',
              body: pieces[i],
              routePath: doc.modulePath ?? AppPaths.hmsHandbok,
              tags: [
                'hms',
                'håndbok',
                doc.category.title,
                doc.shortLabel,
                doc.id,
                if (doc.vedleggNr != null) 'vedlegg ${doc.vedleggNr}',
                ...doc.summary
                    .toLowerCase()
                    .split(RegExp(r'[^a-zæøå0-9]+'))
                    .where((t) => t.length >= 4)
                    .take(8),
              ],
            ),
          );
        }
      } catch (_) {
        // Skip missing asset.
      }
    }
    return out;
  }

  static List<KnowledgeChunk> _iso14000Chunks() {
    final out = <KnowledgeChunk>[
      KnowledgeChunk(
        id: 'hms:iso14000:series',
        source: KnowledgeSourceKind.hms,
        title: Iso14000Guide.seriesTitle,
        body:
            '${Iso14000Guide.seriesSubtitle}\n\n'
            '${Iso14000Guide.disclaimer}\n\n'
            'PDCA: '
            '${Iso14000Guide.pdca.map((s) => '${s.letter} ${s.title} (${s.subtitle}): ${s.points.join('; ')}').join(' | ')}',
        routePath: AppPaths.hmsIso14000,
        tags: const ['iso', '14000', 'miljø', 'hms', 'pdca'],
      ),
    ];
    for (final s in Iso14000Guide.standards) {
      out.add(
        KnowledgeChunk(
          id: 'hms:iso:${s.id}',
          source: KnowledgeSourceKind.hms,
          title: '${s.code} — ${s.title}',
          body:
              '${s.role}\n\n${s.summary}\n\n'
              'For MAVI:\n${s.forMavi.map((e) => '• $e').join('\n')}',
          routePath: s.modulePath ?? AppPaths.hmsIso14000,
          tags: [
            'iso',
            'miljø',
            'hms',
            s.shortTitle,
            s.code,
            s.id,
            if (s.handbookDocId != null) s.handbookDocId!,
          ],
        ),
      );
    }
    return out;
  }

  static List<String> _splitBody(String body) {
    if (body.length <= _maxChunkChars) return [body];
    final parts = <String>[];
    var remaining = body;
    while (remaining.length > _maxChunkChars) {
      var cut = remaining.lastIndexOf('\n\n', _maxChunkChars);
      if (cut < _maxChunkChars ~/ 2) {
        cut = remaining.lastIndexOf('. ', _maxChunkChars);
      }
      if (cut < _maxChunkChars ~/ 2) cut = _maxChunkChars;
      parts.add(remaining.substring(0, cut).trim());
      remaining = remaining.substring(cut).trim();
    }
    if (remaining.isNotEmpty) parts.add(remaining);
    return parts;
  }

  static List<KnowledgeChunk> _sanitize(List<KnowledgeChunk> raw) {
    final out = <KnowledgeChunk>[];
    for (final c in raw) {
      if (!AssistantTextUtils.isUsefulChunk(
        id: c.id,
        title: c.title,
        body: c.body,
      )) {
        continue;
      }
      out.add(
        KnowledgeChunk(
          id: c.id,
          source: c.source,
          title: AssistantTextUtils.cleanTitle(c.title),
          body: AssistantTextUtils.cleanBody(c.body),
          routePath: c.routePath,
          tags: c.tags,
        ),
      );
    }
    return out;
  }

  static List<KnowledgeChunk> _sopChunks(SopTrainingDocument doc) {
    return doc.entries.map((e) {
      final body = e.answer.trim().isEmpty ? e.body : e.answer;
      return KnowledgeChunk(
        id: 'sop:${e.id}',
        source: KnowledgeSourceKind.sop,
        title: e.title.isEmpty
            ? (e.subsection.isEmpty ? e.section : e.subsection)
            : e.title,
        body: body,
        routePath: AppPaths.hmsOpplaering,
        tags: [
          ...e.tags,
          if (e.system != null) e.system!,
          e.section,
          e.subsection,
          e.kind.name,
          doc.title,
        ],
      );
    }).toList();
  }

  static List<KnowledgeChunk> _rentalChunks() {
    final agreement = VehicleRentalAgreement.body(
      registrationNumber: 'EKSEMPEL',
      vehicleMake: 'EKSEMPEL',
    );

    return [
      KnowledgeChunk(
        id: 'rental:approvers',
        source: KnowledgeSourceKind.rental,
        title: 'Godkjenningsrekkefølge bilutleie',
        body:
            'Hvem kan godkjenne / låne ut bil?\n'
            '${VehicleRentalAgreement.approverPriorityText}\n\n'
            'Partner (låntaker) ber om bil via bilutleie i DriftPro. '
            'MAVI må godkjenne før bilen utleveres. '
            'Samme rekkefølge gjelder ved retur.',
        routePath: AppPaths.partners,
        tags: const [
          'bilutleie',
          'godkjenning',
          'jassy',
          'herish',
          'julie',
          'karwan',
          'retur',
          'låne',
          'låne ut',
          'hvem',
          'utleie',
        ],
      ),
      KnowledgeChunk(
        id: 'rental:handout',
        source: KnowledgeSourceKind.rental,
        title: 'Sjekkliste ved utlevering av bil',
        body: VehicleRentalAgreement.handoutChecklist.map((e) => '• $e').join('\n'),
        routePath: AppPaths.partners,
        tags: const ['bilutleie', 'utlevering', 'bilder', 'drivstoff', 'kilometer', 'sjekkliste'],
      ),
      KnowledgeChunk(
        id: 'rental:return',
        source: KnowledgeSourceKind.rental,
        title: 'Sjekkliste ved retur av bil',
        body: VehicleRentalAgreement.returnChecklist.map((e) => '• $e').join('\n'),
        routePath: AppPaths.partners,
        tags: const ['bilutleie', 'retur', 'bilder', 'skader', 'sjekkliste'],
      ),
      KnowledgeChunk(
        id: 'rental:agreement',
        source: KnowledgeSourceKind.rental,
        title: 'Leieavtale for kjøretøy — regler',
        body: agreement,
        routePath: AppPaths.partners,
        tags: const [
          'bilutleie',
          'leieavtale',
          'pris',
          'forsikring',
          'egenandel',
          'bøter',
          'drivstoff',
          'bompenger',
        ],
      ),
      const KnowledgeChunk(
        id: 'rental:price',
        source: KnowledgeSourceKind.rental,
        title: 'Pris og gebyrer for bilutleie',
        body:
            'Leiepris er 1.000,- pr påbegynte dag. Drivstoff etterfylles til samme nivå '
            'som ved utlevering; manglende etterfylling gir administrasjonsgebyr 500,- '
            'ekskl. drivstoff. Bompenger, vask og service ved lang leie er inkludert. '
            'Fakturering skjer ved motregning på oppsummering.',
        routePath: AppPaths.partners,
        tags: ['pris', 'gebyr', 'drivstoff', 'bompenger', 'faktura', 'bilutleie'],
      ),
    ];
  }

  static List<KnowledgeChunk> _helpChunks() {
    return [
      const KnowledgeChunk(
        id: 'help:start',
        source: KnowledgeSourceKind.help,
        title: 'Kom i gang med DriftPro',
        body:
            'DriftPro er en skybasert plattform for hele bedriften. '
            'Du logger inn med ansattnummer og passord (eller partner-brukernavn). '
            'Konto opprettes av administrator — det er ikke offentlig selvregistrering. '
            'Dashbord gir daglig oversikt. Fravær: søk ferie og egenmelding — leder godkjenner. '
            'HMS: meld avvik, fyll SJA og se vernerunder. Mer: personalmappe, profil og hjelp.',
        routePath: AppPaths.moreHjelp,
        tags: ['innlogging', 'start', 'ansattnummer', 'passord', 'onboarding'],
      ),
      KnowledgeChunk(
        id: 'help:absence',
        source: KnowledgeSourceKind.help,
        title: 'Fravær og ferie',
        body:
            'Fraværsmodulen dekker søknad til godkjenning. Leder ser ventende saker under Godkjenn. '
            'Typer: ferie, egenmelding, sykt barn, permisjon og sykmelding. '
            'Saldo og kvoter per ansatt og år. Dobbel kalender for ferie og fravær. '
            'Røde dager og Lovdata-regelhjelp er innebygd. '
            'Superadmin kan registrere ferie direkte uten godkjenningskø.',
        routePath: AppPaths.moreHjelp,
        tags: ['fravær', 'ferie', 'egenmelding', 'permisjon', 'sykmelding', 'kvote'],
      ),
      KnowledgeChunk(
        id: 'help:hms',
        source: KnowledgeSourceKind.help,
        title: 'HMS — kvalitet og sikkerhet',
        body:
            'HMS-huben samler avvik (bilder, GPS, alvorlighet), risikoanalyse (ROS 5×5), '
            'SJA med maler og signatur, vernerunder, maskiner/utstyr, kompetansematrise, '
            'DMS for håndbok, og anonym varsling. Et avvik kan kobles til risikoanalyse. '
            'Anonym anmeldelse ligger under Mer → Anonym anmeldelse (kun til Tommy/Nico/Hazher).',
        routePath: AppPaths.moreHjelp,
        tags: [
          'hms',
          'avvik',
          'sja',
          'vernerunde',
          'risiko',
          'kompetanse',
          'dms',
          'anonym',
          'varsling',
        ],
      ),
      KnowledgeChunk(
        id: 'help:partners',
        source: KnowledgeSourceKind.help,
        title: 'Partnere, ruter og logistikk',
        body:
            'Partnermodulen dekker Brreg, kjøretøy, EU-kontroll, rute-PDF, publisering, '
            'sjåfør- og eierportal, SMS fra rute-PDF, bilutleie og inspeksjon. '
            'Ruter kan komme fra manuell opplasting, mass auto, AUTO MASS eller '
            'SAP e-post innboks (ruter@driftpro.no).',
        routePath: AppPaths.moreHjelp,
        tags: ['partner', 'rute', 'sap', 'sms', 'bilutleie', 'brreg', 'sjåfør'],
      ),
      KnowledgeChunk(
        id: 'help:password',
        source: KnowledgeSourceKind.help,
        title: 'Bytt passord',
        body:
            'Ansatte logger inn med ansattnummer. Standardpassord ved ny bruker er 000000. '
            'Du kan bytte passord selv under Mer → Min profil → Bytt passord. '
            'Passordet må være minst 6 tegn.',
        routePath: AppPaths.moreProfil,
        tags: ['passord', 'innlogging', 'profil', 'sikkerhet', '000000'],
      ),
      KnowledgeChunk(
        id: 'help:support',
        source: KnowledgeSourceKind.help,
        title: 'Kontakt support',
        body:
            'Har du spørsmål om innlogging, ruter, HMS, fravær eller tilganger? '
            'Send e-post til hazher@mavilogistikk.no. '
            'Support-side: https://hazher.no/DRIFTPRO/Support/.',
        routePath: AppPaths.moreHjelp,
        tags: ['support', 'hjelp', 'kontakt', 'e-post'],
      ),
    ];
  }

  static List<KnowledgeChunk> _catalogChunks() {
    final out = <KnowledgeChunk>[];
    var i = 0;
    for (final group in DriftProPlatformCatalog.groups) {
      for (final f in group.features) {
        i++;
        final highlights = f.highlights.map((h) => '• $h').join('\n');
        out.add(
          KnowledgeChunk(
            id: 'catalog:$i',
            source: KnowledgeSourceKind.help,
            title: '${group.title}: ${f.title}',
            body: [
              f.description,
              if (highlights.isNotEmpty) highlights,
            ].join('\n'),
            routePath: AppPaths.moreOm,
            tags: [group.title, f.title, ...f.highlights],
          ),
        );
      }
    }
    return out;
  }
}
