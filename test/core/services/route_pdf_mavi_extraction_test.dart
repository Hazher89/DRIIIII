import 'package:flutter_test/flutter_test.dart';
import 'package:driftpro/core/services/partner/route_pdf_text_service.dart';

void main() {
  group('MAVI fra PDF-tekst', () {
    test('finner NO_O_M0042 ved Resource ID / Trip Overview', () {
      const text = '''
Trip Overview
Resource ID NO_O_M0042
Start date 24.04.26
''';
      expect(RoutePdfTextService.parseResourceId(text), 'M42');
    });

    test('finner M-kode etter Resource ID-label', () {
      const text = 'Trip Overview\nResource ID: M17\nStart date 01.01.26';
      expect(RoutePdfTextService.parseResourceId(text), 'M17');
    });

    test('leser MAVI fra filnavn (_M24, NO_O_M0024)', () {
      expect(
        RoutePdfTextService.extractResourceIdFromFileName(
          '13f4530b-9a2c-4f67-9590-0b29981d9949_M24_KVELD.pdf',
        ),
        'M24',
      );
      expect(
        RoutePdfTextService.extractResourceIdFromFileName('8785f8a4_M24.pdf'),
        'M24',
      );
      expect(
        RoutePdfTextService.extractResourceIdFromFileName('NO_O_M0099_route.pdf'),
        'M99',
      );
    });

    test('NO_O_M0045Resource ID (glued) — ikke M27 fra Lillestrøm-dato', () {
      const text = '''
Trip Overview
NO_O_M0045Resource ID
Obaidah 045 045 obaidahDriver Name
Seq Freight Unit
1 customer Lillestrøm 27.04.2026 17:00:00
''';
      expect(RoutePdfTextService.parseResourceId(text), 'M45');
    });

    test('NO_O_M0021Resource ID — ikke M14 fra dato', () {
      const text = '''
Trip Overview
NO_O_M0021Resource ID
Mohamed 021 021 mohamedDriver Name
Seq Freight Unit
Christine Kværnæs Lillestrøm 14.04.2026 17:00:00
''';
      expect(RoutePdfTextService.parseResourceId(text), 'M21');
    });
  });
}
