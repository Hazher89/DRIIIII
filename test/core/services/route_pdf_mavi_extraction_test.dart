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

    test('NO_O_M0JIM — navnebasert Resource ID', () {
      const text = '''
Trip Overview
Freight Order 6102948737
Resource ID
NO_O_M0JIM
Driver Name
Jim jim
Seq Freight Unit
''';
      expect(RoutePdfTextService.parseResourceId(text), 'MJIM');
      expect(
        RoutePdfTextService.normalizeUnitCodeForMatch('NO_O_M0JIM'),
        'MJIM',
      );
    });

    test('matcher bil via MJIM / sjåførnavn Jim', () {
      final vehicles = [
        (
          id: 'v1',
          unit: 'NO_O_M0JIM',
          driver: 'Jim jim',
        ),
      ];
      final map = RoutePdfTextService.buildVehicleLookupMap(
        vehicles: vehicles,
        unitCodeOf: (v) => v.unit,
        driverNameOf: (v) => v.driver,
      );
      expect(RoutePdfTextService.findVehicleInLookup(map, 'MJIM')?.id, 'v1');
      expect(
        RoutePdfTextService.findVehicleInLookup(map, null, driverName: 'Jim jim')?.id,
        'v1',
      );
    });
  });
}
