import 'assistant_corpus.dart';
import 'knowledge_assistant_engine.dart';
import '../supabase_service.dart';

/// DriftPro kunnskaps-chat: lokal søk + valgfri Gemini (RAG).
class KnowledgeAssistantService {
  KnowledgeAssistantService._();

  static final KnowledgeAssistantService instance = KnowledgeAssistantService._();

  KnowledgeAssistantEngine? _engine;
  bool _loading = false;

  static const suggestedQueries = [
    'Hvordan behandle kolli Undelivered?',
    'Hva koster bilutleie per dag?',
    'Hvordan bytter jeg passord?',
    'Hvem godkjenner bilutleie?',
    'Hvem kan låne ut bil?',
    'Hvordan søker jeg ferie?',
    'Hva er sjekklisten ved retur av bil?',
    'Morgenrutine plukking',
    'Hvordan melder jeg avvik?',
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

    final hits = engine.search(query, limit: 6);
    final local = engine.answer(query, limit: 4);

    // Prøv Gemini med RAG-kontekst. Faller tilbake til lokalt svar.
    try {
      final gemini = await _askGemini(query, hits);
      if (gemini != null && gemini.trim().isNotEmpty) {
        return KnowledgeAnswer(
          found: hits.isNotEmpty || local.found,
          hits: hits.take(3).toList(),
          text: gemini.trim(),
        );
      }
    } catch (_) {
      // Lokal fallback.
    }

    return local;
  }

  Future<String?> _askGemini(String question, List<KnowledgeHit> hits) async {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return null;

    final contexts = <Map<String, String>>[
      for (final h in hits)
        {
          'title': h.chunk.title,
          'source': h.chunk.sourceLabel,
          'body': h.chunk.body.length > 1600
              ? h.chunk.body.substring(0, 1600)
              : h.chunk.body,
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
