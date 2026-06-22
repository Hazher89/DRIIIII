import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driftpro/core/services/hms/sop_training_parser.dart';
import 'package:driftpro/core/services/hms/sop_training_search.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String xml;
  setUpAll(() {
    final file = File('assets/hms/sop_hub_driftsrutiner_v4_8.docx');
    final bytes = file.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final docFile = archive.files.firstWhere((f) => f.name == 'word/document.xml');
    xml = utf8.decode(docFile.content as List<int>);
  });

  test('parser uses utf8 and correct version', () {
    final doc = SopTrainingParser.parseDocumentXml(xml);
    expect(doc.documentNumber, 'SOP-HUB-001');
    expect(doc.version, '4.0');
    expect(doc.entries.first.title, isNot(contains('Ã')));
  });

  test('semantic search finds undelivered handling', () {
    final doc = SopTrainingParser.parseDocumentXml(xml);
    final engine = SopTrainingSearchEngine(doc.entries)..buildIndex();
    final hits = engine.search('hvordan behandle kolli Undelivered');
    expect(hits, isNotEmpty);

    final top = hits.first;
    expect(
      top.answer.toLowerCase(),
      anyOf(
        contains('scann'),
        contains('rebook'),
        contains('avbestill'),
      ),
    );
    expect(top.confidence, greaterThan(0.5));
  });

  test('hubanero returns multiple hits', () {
    final doc = SopTrainingParser.parseDocumentXml(xml);
    final engine = SopTrainingSearchEngine(doc.entries)..buildIndex();
    final hits = engine.search('hubanero');
    expect(hits.length, greaterThan(3));
  });
}
