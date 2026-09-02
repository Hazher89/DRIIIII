import 'assistant_corpus.dart';
import 'assistant_leave_intelligence.dart';
import 'assistant_memory_service.dart';
import 'assistant_route_intelligence.dart';
import 'assistant_text_utils.dart';
import 'knowledge_assistant_engine.dart';
import '../supabase_service.dart';

/// DriftPro-assistent: FAQ + live ruter + live fravær (GDPR) + kontinuerlig læring.
class KnowledgeAssistantService {
  KnowledgeAssistantService._();

  static final KnowledgeAssistantService instance = KnowledgeAssistantService._();

  KnowledgeAssistantEngine? _engine;
  bool _loading = false;

  static const suggestedQueries = [
    'Hvor har M09 kjørt i det siste?',
    'Hvor mange kunder har M08 hatt den siste uken?',
    'Hvor mange ganger ble ruten endret på M62?',
    'Hvor mye ferie har jeg igjen?',
    'Hvor mange egenmeldingsdager har jeg?',
    'Hvem kan sende anmeldelse anonymt?',
    'Hvordan melder jeg avvik?',
    'Hvordan bytter jeg passord?',
    'Hva koster bilutleie per dag?',
    'Hvem godkjenner bilutleie?',
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
      final chunks = await AssistantCorpus.build();
      final engine = KnowledgeAssistantEngine(chunks)..buildIndex();
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
        text: 'Assistenten kunne ikke lastes. Prøv igjen.',
      );
    }

    // 1) Fravær/ferie med GDPR — før alt annet.
    try {
      final leave = await AssistantLeaveIntelligence.tryAnswer(query);
      if (leave != null && leave.trim().isNotEmpty) {
        return KnowledgeAnswer(found: true, hits: const [], text: leave.trim());
      }
    } catch (_) {}

    // 2) Live ruter for alle biler.
    try {
      final live = await AssistantRouteIntelligence.tryAnswer(query);
      if (live != null && live.trim().isNotEmpty) {
        return KnowledgeAnswer(found: true, hits: const [], text: live.trim());
      }
    } catch (_) {}

    // 3) Lært minne + kunnskapsbase (+ Gemini).
    final hits = engine.search(query, limit: 8);
    final memoryHits = await _memoryAsHits(query);
    final mergedHits = [...memoryHits, ...hits];
    final local = engine.answer(query, limit: 4);

    try {
      final gemini = await _askGemini(query, mergedHits);
      if (gemini != null && gemini.trim().isNotEmpty) {
        final profile = await SupabaseService.fetchCurrentUserProfile();
        if (profile?.companyId != null) {
          await AssistantMemoryService.remember(
            companyId: profile!.companyId!,
            kind: 'qa',
            content: gemini.trim(),
            visibility: 'company',
            sourceQuery: query,
          );
        }
        return KnowledgeAnswer(
          found: mergedHits.isNotEmpty || local.found,
          hits: mergedHits.take(3).toList(),
          text: gemini.trim(),
        );
      }
    } catch (_) {}

    if (local.found) {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      if (profile?.companyId != null) {
        await AssistantMemoryService.remember(
          companyId: profile!.companyId!,
          kind: 'qa',
          content: local.text,
          visibility: 'company',
          sourceQuery: query,
        );
      }
    }

    return local;
  }

  Future<List<KnowledgeHit>> _memoryAsHits(String query) async {
    final profile = await SupabaseService.fetchCurrentUserProfile();
    if (profile == null) return const [];
    final memories = await AssistantMemoryService.recall(viewer: profile);
    if (memories.isEmpty) return const [];

    final q = query.toLowerCase();
    final scored = <KnowledgeHit>[];
    for (final m in memories) {
      final body = m.content;
      final hay = body.toLowerCase();
      var score = 8.0;
      for (final t in q.split(RegExp(r'\s+'))) {
        if (t.length >= 3 && hay.contains(t)) score += 10;
      }
      if (score < 18) continue;
      scored.add(
        KnowledgeHit(
          chunk: KnowledgeChunk(
            id: 'memory:${m.id}',
            source: KnowledgeSourceKind.help,
            title: 'Lært: ${m.kind}',
            body: body,
            tags: [m.kind, if (m.subjectKey != null) m.subjectKey!],
          ),
          score: score,
          snippet: body.length > 160 ? '${body.substring(0, 160)}…' : body,
        ),
      );
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(4).toList();
  }

  Future<String?> _askGemini(String question, List<KnowledgeHit> hits) async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return null;

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
            'body': AssistantTextUtils.cleanBody(h.chunk.body).length > 1600
                ? AssistantTextUtils.cleanBody(h.chunk.body).substring(0, 1600)
                : AssistantTextUtils.cleanBody(h.chunk.body),
          },
    ];

    if (contexts.isEmpty) {
      for (final h in engineSearchFallback(question)) {
        contexts.add({
          'title': h.chunk.title,
          'source': h.chunk.sourceLabel,
          'body': h.chunk.body.length > 1200
              ? h.chunk.body.substring(0, 1200)
              : h.chunk.body,
        });
      }
    }

    final res = await SupabaseService.client.functions.invoke(
      'driftpro-assistant',
      body: {
        'question': question,
        'contexts': contexts,
      },
      headers: {'Authorization': 'Bearer $token'},
    );

    final data = res.data;
    if (data is Map && data['error'] != null) {
      final err = '${data['error']}';
      if (err.contains('gemini_not_configured') ||
          err.contains('GEMINI_API_KEY')) {
        return null;
      }
      throw Exception(data['message'] ?? err);
    }
    if (data is Map && data['answer'] is String) {
      return data['answer'] as String;
    }
    return null;
  }

  List<KnowledgeHit> engineSearchFallback(String query) {
    return _engine?.search(query, limit: 5) ?? const [];
  }

  Future<List<KnowledgeHit>> search(String query, {int limit = 8}) async {
    await ensureReady();
    return _engine?.search(query, limit: limit) ?? const [];
  }
}
