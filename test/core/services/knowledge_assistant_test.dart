import 'package:flutter_test/flutter_test.dart';
import 'package:driftpro/core/services/assistant/assistant_corpus.dart';
import 'package:driftpro/core/services/assistant/knowledge_assistant_engine.dart';

void main() {
  test('rental and help corpus answers common questions', () async {
    final chunks = await AssistantCorpus.build();
    expect(chunks, isNotEmpty);

    final engine = KnowledgeAssistantEngine(chunks)..buildIndex();

    final price = engine.answer('Hva koster bilutleie per dag?');
    expect(price.found, isTrue);
    expect(
      price.text.toLowerCase(),
      anyOf(contains('1000'), contains('1.000'), contains('pris')),
    );
    expect(
      price.hits.first.chunk.source,
      KnowledgeSourceKind.rental,
    );

    final pw = engine.answer('Hvordan bytter jeg passord?');
    expect(pw.found, isTrue);
    expect(pw.text.toLowerCase(), anyOf(contains('passord'), contains('profil')));

    final who = engine.answer('hvem kan låne ut bil?');
    expect(who.found, isTrue);
    expect(who.hits.first.chunk.source, KnowledgeSourceKind.rental);
    expect(
      who.text.toLowerCase(),
      anyOf(contains('jassy'), contains('godkjenn'), contains('herish')),
    );
  });
}
