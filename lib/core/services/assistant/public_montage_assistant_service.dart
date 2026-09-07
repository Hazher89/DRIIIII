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
    'Hva er inkludert i InstallWash?',
    'Kan dere henge TV på vegg?',
    'Hva må jeg gjøre før komfyrlevering?',
    'Er side-by-side (SBS) en enkel eller avansert tjeneste?',
    'Hva er ikke inkludert ved omhengsling (TurnDoor)?',
    'Når kontakter montør meg for avansert montering?',
  ];

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

    final hits = _rankMontageHits(
      q,
      [
        ...engine.search(q, limit: 10),
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
          'Prøv å spørre om en konkret tjeneste (f.eks. vaskemaskin, komfyr, '
          'TV på vegg) — hva som er inkludert, hva du må gjøre, eller hva '
          'som ikke er inkludert.\n\n'
          'For booking eller pris: kontakt butikken der du handlet.',
    );
  }

  /// Sørg for at sterke stikkord (TurnDoor, omhengsling) alltid er blant kandidatene.
  List<KnowledgeHit> _forcedTagHits(String query) {
    final q = query.toLowerCase();
    final out = <KnowledgeHit>[];
    for (final chunk in MontageServicesCorpus.chunks()) {
      var force = false;
      for (final tag in chunk.tags) {
        if (tag.length >= 4 && q.contains(tag.toLowerCase())) force = true;
      }
      final code = RegExp(r'install[a-z]+|tvon[a-z]+|turndoor', caseSensitive: false)
          .firstMatch(chunk.title)
          ?.group(0)
          ?.toLowerCase();
      if (code != null && q.contains(code)) force = true;
      if (q.contains('omheng') && chunk.id.contains('turndoor')) force = true;
      if (!force) continue;
      out.add(
        KnowledgeHit(
          chunk: chunk,
          score: 50,
          snippet: chunk.body.length > 120
              ? '${chunk.body.substring(0, 120)}…'
              : chunk.body,
        ),
      );
    }
    return out;
  }

  /// Preferer treff der spørsmålet nevner tjenestekode/tag (InstallWash, omhengsling…).
  List<KnowledgeHit> _rankMontageHits(String query, List<KnowledgeHit> hits) {
    final seen = <String>{};
    final unique = <KnowledgeHit>[];
    for (final h in hits) {
      if (seen.add(h.chunk.id)) unique.add(h);
    }

    final q = query.toLowerCase();
    final scored = <({KnowledgeHit hit, double bonus})>[];
    for (final h in unique) {
      var bonus = h.score;
      final title = h.chunk.title.toLowerCase();
      final id = h.chunk.id.toLowerCase();
      for (final tag in h.chunk.tags) {
        final t = tag.toLowerCase();
        if (t.length >= 4 && q.contains(t)) bonus += 120;
      }
      final code = RegExp(r'install[a-z]+|tvon[a-z]+|turndoor', caseSensitive: false)
          .firstMatch(h.chunk.title)
          ?.group(0)
          ?.toLowerCase();
      if (code != null && q.contains(code)) bonus += 160;
      if (q.contains('omheng') && (id.contains('turndoor') || title.contains('omheng'))) {
        bonus += 200;
      }
      if (q.contains('vask') && id.contains('wash')) bonus += 140;
      if ((q.contains('vegg') || q.contains('oppheng')) && id.contains('tvwall')) {
        bonus += 140;
      }
      if (q.contains('sbs') || q.contains('side-by-side') || q.contains('side by side')) {
        if (id.contains('sbs')) bonus += 160;
      }
      scored.add((hit: h, bonus: bonus));
    }
    scored.sort((a, b) => b.bonus.compareTo(a.bonus));
    return [
      for (final s in scored)
        KnowledgeHit(chunk: s.hit.chunk, score: s.bonus, snippet: s.hit.snippet),
    ];
  }

  KnowledgeAnswer _composeLocal(String query, List<KnowledgeHit> hits) {
    if (hits.isEmpty || hits.first.score < 12) {
      return const KnowledgeAnswer(found: false, hits: [], text: '');
    }
    final primary = hits.first;
    final related = hits.skip(1).take(2).toList();
    final buf = StringBuffer()
      ..writeln(primary.chunk.title)
      ..writeln()
      ..write(primary.chunk.body.trim());
    if (related.isNotEmpty) {
      buf.writeln();
      buf.writeln();
      buf.writeln('Se også:');
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

    // Alltid send oversikt hvis tomt.
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
    if (data is Map && data['error'] != null) {
      final err = '${data['error']}';
      if (err.contains('gemini_not_configured') ||
          err.contains('GEMINI_API_KEY') ||
          err.contains('rate_limited')) {
        return null;
      }
      return null;
    }
    if (data is Map && data['answer'] is String) {
      return data['answer'] as String;
    }
    return null;
  }
}
