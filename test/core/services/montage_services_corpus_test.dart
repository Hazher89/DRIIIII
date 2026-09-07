import 'package:flutter_test/flutter_test.dart';

import 'package:driftpro/core/services/assistant/montage_services_corpus.dart';
import 'package:driftpro/core/services/assistant/public_montage_assistant_service.dart';

void main() {
  test('InstallWash includes water connection', () async {
    final a = await PublicMontageAssistantService.instance.ask(
      'Hva er inkludert i InstallWash?',
    );
    expect(a.found, isTrue);
    expect(a.text.toLowerCase(), contains('vann'));
    expect(a.hits.first.chunk.id, contains('wash'));
  });

  test('TV on wall mentions excluded wifi', () async {
    final a = await PublicMontageAssistantService.instance.ask(
      'Kan dere henge TV på vegg? Hva er ikke inkludert?',
    );
    expect(a.found, isTrue);
    expect(a.hits.first.chunk.id, contains('tvwall'));
    expect(a.text.toLowerCase(), anyOf(contains('wifi'), contains('kanalsøk')));
  });

  test('TurnDoor is omhengsling', () async {
    final a = await PublicMontageAssistantService.instance.ask(
      'Hva er inkludert ved omhengsling TurnDoor?',
    );
    expect(a.found, isTrue);
    expect(a.hits.first.chunk.id, contains('turndoor'));
  });

  test('SBS is advanced service', () async {
    final a = await PublicMontageAssistantService.instance.ask(
      'Er side-by-side SBS enkel eller avansert?',
    );
    expect(a.found, isTrue);
    expect(a.hits.any((h) => h.chunk.id.contains('sbs')), isTrue);
  });

  test('corpus has overview and services', () {
    final chunks = MontageServicesCorpus.chunks();
    expect(chunks.length, greaterThan(10));
    expect(chunks.first.id, MontageServicesCorpus.overviewId);
  });

  test('natural language vaskemaskin maps to wash', () async {
    final a = await PublicMontageAssistantService.instance.ask(
      'Hva er inkludert når dere monterer vaskemaskinen min?',
    );
    expect(a.found, isTrue);
    expect(a.hits.first.chunk.id, contains('wash'));
  });

  test('natural language komfyr maps to cooker', () async {
    final a = await PublicMontageAssistantService.instance.ask(
      'Hva må jeg gjøre klart før komfyren kommer?',
    );
    expect(a.found, isTrue);
    expect(a.hits.first.chunk.id, contains('cooker'));
  });

  test('natural language omhengsling without code', () async {
    final a = await PublicMontageAssistantService.instance.ask(
      'Hva dekker omhengsling av dør?',
    );
    expect(a.found, isTrue);
    expect(a.hits.first.chunk.id, contains('turndoor'));
  });
}
