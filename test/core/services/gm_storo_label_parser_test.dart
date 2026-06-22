import 'package:flutter_test/flutter_test.dart';

import 'package:driftpro/core/services/gm_storo/gm_storo_label_parser.dart';

void main() {
  const storoSample = '''
From Elgiganten Logistik AB
To ELKJOP STORO
INDUSTRIVEIEN 3
1400 SKI
U42 AREA: B, C, D
Consignee 1526
Package 432536711
Weight 143,3 kg
Article EG 783443
SSCC 373000005303896027
Shipment 2508070479
Ready Time 09:30
Article NDC EFI622E94E
''';

  const gmSample = '''
To ELKJOP GLASMAGASINET
STORTORGET 9
0155 OSLO
Consignee 1059
Package 432728282
Weight 64,5 kg
SSCC 373000005305647993
Shipment 2508143576
Ready Time 09:30
''';

  test('parses STORO label fields', () {
    final d = GmStoroLabelParser.parseOcrText(storoSample);
    expect(d.destination, 'storo');
    expect(d.sscc, '373000005303896027');
    expect(d.packageId, '432536711');
    expect(d.shipmentId, '2508070479');
    expect(d.consignee, '1526');
    expect(d.readyTime, '09:30');
    expect(d.articleEg, '783443');
    expect(d.articleNdc, 'EFI622E94E');
  });

  test('parses GM Glasmagasinet label', () {
    final d = GmStoroLabelParser.parseOcrText(gmSample);
    expect(d.destination, 'gm');
    expect(d.sscc, '373000005305647993');
    expect(d.packageId, '432728282');
    expect(d.consignee, '1059');
  });

  test('parses barcode SSCC', () {
    final d = GmStoroLabelParser.parseBarcode('(00)373000005303894849');
    expect(d.sscc, '373000005303894849');
  });

  test('normalize sscc strips prefix', () {
    expect(
      GmStoroLabelParser.normalizeSscc('00373000005303896027'),
      '373000005303896027',
    );
  });
}
