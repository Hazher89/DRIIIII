import 'package:driftpro/core/hms/hms_prose.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('regler blir punkter og kilde fjernes', () {
    const raw = '''
Rutiner til samarbeidspartnere
Kilde: Rutiner til samarbeidspartnere.docx (Landax / MAVI)

Rutiner til samarbeidspartnere
Alltid kom på jobb med full uniform og arbeidssko.
Ingen får hoppe opp eller ned av rampen.
Sorter og kast søppel på riktig måte.
''';
    final out = HmsProse.format(raw);
    expect(out.contains('Kilde:'), isFalse);
    expect(out.contains('• Alltid kom på jobb'), isTrue);
    expect(out.contains('• Ingen får hoppe'), isTrue);
    expect('Rutiner til samarbeidspartnere'.allMatches(out).length, 1);
  });

  test('avsnitt som er brutt over linjer, settes sammen', () {
    const raw = '''
Oppgaven er todelt. Første del
innebærer å hente rutene.
''';
    final out = HmsProse.format(raw);
    expect(
      out,
      contains('Første del innebærer å hente rutene.'),
    );
  });
}
