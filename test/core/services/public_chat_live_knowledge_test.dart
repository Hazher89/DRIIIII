import 'package:driftpro/core/services/assistant/assistant_corpus.dart';
import 'package:driftpro/core/services/assistant/knowledge_assistant_engine.dart';
import 'package:driftpro/core/services/assistant/public_montage_assistant_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('live closing-hours rule answers når stenger dere', () async {
    final chunks = <KnowledgeChunk>[
      const KnowledgeChunk(
        id: 'live.test-close',
        source: KnowledgeSourceKind.liveTrain,
        title: 'vi stenger',
        body: 'vi stenger KL 17:00 hverdager.',
        tags: ['rule', 'live', 'trained', 'stenger'],
      ),
      const KnowledgeChunk(
        id: 'live.test-sound',
        source: KnowledgeSourceKind.liveTrain,
        title: 'Lydplanke',
        body: 'vi monterer ikke lydplanke.',
        tags: ['rule', 'live', 'trained'],
      ),
    ];

    // Inject engine without network.
    final engine = KnowledgeAssistantEngine(chunks)..buildIndex();
    // ignore: invalid_use_of_visible_for_testing_member
    PublicMontageAssistantService.instance.debugSetEngineForTest(engine, liveCount: 2);

    final answer =
        await PublicMontageAssistantService.instance.ask('når stenger dere?');

    expect(answer.found, isTrue);
    expect(answer.text.toLowerCase(), contains('17'));
    expect(answer.text.toLowerCase(), isNot(contains('dessverre ikke')));
  });
}
