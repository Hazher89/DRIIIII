import 'package:driftpro/core/services/assistant/assistant_corpus.dart';
import 'package:driftpro/core/services/assistant/knowledge_assistant_engine.dart';
import 'package:driftpro/core/services/assistant/montage_services_corpus.dart';
import 'package:driftpro/core/services/assistant/public_montage_assistant_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Netflix TV question must not answer lydplanke', () async {
    final chunks = <KnowledgeChunk>[
      ...MontageServicesCorpus.chunks(),
      const KnowledgeChunk(
        id: 'live.soundbar',
        source: KnowledgeSourceKind.liveTrain,
        title: 'Lydplanke',
        body: 'vi monterer ikke lydplanke.',
        tags: ['rule', 'live', 'trained'],
      ),
      const KnowledgeChunk(
        id: 'live.close',
        source: KnowledgeSourceKind.liveTrain,
        title: 'vi stenger',
        body: 'vi stenger KL 17:00 hverdager.',
        tags: ['rule', 'live', 'trained', 'stenger'],
      ),
    ];
    final engine = KnowledgeAssistantEngine(chunks)..buildIndex();
    PublicMontageAssistantService.instance
        .debugSetEngineForTest(engine, liveCount: 2);

    final answer = await PublicMontageAssistantService.instance.ask(
      'kan dere sette opp netflix for kunden når dere monterer en TV?',
    );

    expect(answer.found, isTrue);
    expect(answer.text.toLowerCase(), isNot(contains('lydplanke')));
    expect(
      answer.text.toLowerCase(),
      anyOf(
        contains('netflix'),
        contains('wifi'),
        contains('oppsett'),
        contains('ikke'),
      ),
    );
  });

  test('closing hours still uses live rule', () async {
    final chunks = <KnowledgeChunk>[
      ...MontageServicesCorpus.chunks(),
      const KnowledgeChunk(
        id: 'live.close',
        source: KnowledgeSourceKind.liveTrain,
        title: 'vi stenger',
        body: 'vi stenger KL 17:00 hverdager.',
        tags: ['rule', 'live', 'trained', 'stenger'],
      ),
    ];
    final engine = KnowledgeAssistantEngine(chunks)..buildIndex();
    PublicMontageAssistantService.instance
        .debugSetEngineForTest(engine, liveCount: 1);

    final answer =
        await PublicMontageAssistantService.instance.ask('når stenger dere?');
    expect(answer.found, isTrue);
    expect(answer.text.toLowerCase(), contains('17'));
  });
}
