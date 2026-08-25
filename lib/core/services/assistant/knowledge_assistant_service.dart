import 'assistant_corpus.dart';
import 'knowledge_assistant_engine.dart';

/// Facade for DriftPro kunnskaps-chat (100 % lokal, ingen betalt AI).
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
    return engine.answer(query);
  }

  Future<List<KnowledgeHit>> search(String query, {int limit = 8}) async {
    await ensureReady();
    return _engine?.search(query, limit: limit) ?? const [];
  }
}
