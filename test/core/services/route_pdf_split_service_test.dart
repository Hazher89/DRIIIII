import 'package:flutter_test/flutter_test.dart';
import 'package:driftpro/core/services/partner/route_pdf_split_service.dart';

void main() {
  group('RoutePdfSplitService.isRouteStartPageText', () {
    test('Trip Overview + Resource ID er start', () {
      expect(
        RoutePdfSplitService.isRouteStartPageText('''
Trip Overview
NO_O_M0045Resource ID
Obaidah Driver Name
Stowing Lane 17B
'''),
        isTrue,
      );
    });

    test('stopp-liste uten overview er ikke start', () {
      expect(
        RoutePdfSplitService.isRouteStartPageText('''
Seq Freight Unit
1 Customer Name Oslo 0150 +47 90000000
2 Another Stop Bergen 5003
'''),
        isFalse,
      );
    });

    test('Resource ID + Driver Name + Stowing uten Trip Overview', () {
      expect(
        RoutePdfSplitService.isRouteStartPageText('''
Resource ID NO_O_M0021
Mohamed Driver Name
Stowing Lane 3
'''),
        isTrue,
      );
    });
  });
}
