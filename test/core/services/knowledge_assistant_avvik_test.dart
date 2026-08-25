import 'package:flutter_test/flutter_test.dart';
import 'package:driftpro/core/services/assistant/assistant_corpus.dart';
import 'package:driftpro/core/services/assistant/knowledge_assistant_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('avvik query prefers dedicated guide over generic help', () async {
    final chunks = await AssistantCorpus.build();
    final bad = chunks.where(
      (c) =>
          c.title.contains('<') ||
          c.body.contains('<!DOCTYPE') ||
          c.id.contains('_err'),
    );
    expect(bad, isEmpty, reason: 'Corpus must not contain HTML or load errors');

    final engine = KnowledgeAssistantEngine(chunks)..buildIndex();
    final hits = engine.search('hvordan registere avvik', limit: 6);
    expect(hits, isNotEmpty);

    final topIds = hits.take(3).map((h) => h.chunk.id).toList();
    expect(
      topIds.any((id) => id.contains('avvik')),
      isTrue,
      reason: 'Expected avvik guide in top hits, got: $topIds',
    );

    final answer = engine.answer('hvordan registere avvik');
    expect(answer.found, isTrue);
    expect(answer.text.toLowerCase(), contains('nytt avvik'));
    expect(answer.text.toLowerCase(), isNot(contains('ifølge hjel')));
  });
}
