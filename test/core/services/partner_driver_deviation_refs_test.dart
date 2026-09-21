import 'package:flutter_test/flutter_test.dart';
import 'package:driftpro/core/services/partner/partner_driver_deviation_refs.dart';
import 'package:driftpro/core/services/partner/route_pdf_text_service.dart';

void main() {
  group('PartnerDriverDeviationRefs', () {
    test('skiller bilag (2…) fra freight unit (4…)', () {
      expect(PartnerDriverDeviationRefs.isBilagNumber('2123831828'), isTrue);
      expect(PartnerDriverDeviationRefs.isFreightUnit('4106155580'), isTrue);
      expect(
        PartnerDriverDeviationRefs.primaryBilag(
          salesOrder: '2123831828',
          freightRaw: '4106155580',
        ),
        '2123831828',
      );
      expect(
        PartnerDriverDeviationRefs.primaryBilag(freightRaw: '4106155580'),
        isNull,
      );
      expect(
        PartnerDriverDeviationRefs.primaryFreightUnit('4106155580'),
        '4106155580',
      );
    });

    test('picker-label viser bilag før FU', () {
      final label = PartnerDriverDeviationRefs.customerPickerLabel(
        name: 'Espen Sevendal',
        freightRaw: '4106155580',
        salesOrder: '2123831828',
        sequence: 3,
      );
      expect(label, contains('Bilag 2123831828'));
      expect(label, contains('FU 4106155580'));
      expect(label, contains('Espen Sevendal'));
    });
  });

  group('Sales order fra rute-PDF', () {
    test('Espen Sevendal: forsiden 4… → detalj bilag 2…', () {
      // Realistisk tekst: Trip Overview (FU 4…) + detaljside (Sales order 2…).
      const raw = '''
Seq Freight Unit Customer Name Services Start Time End Time
1 4106184116 Joanna Jolanta Grochowska , Ovenbakken 16 Bu0102 1361 Østerås , +47 (91886979) SITE DEVUN 08:00 17:00
3 4106155580 Espen Sevendal , Løkebergkroken 12 1344 Haslum , +47 (97029756) SITE 08:00 17:00
5 4106217368 Nor Cosmetics As , Industriveien 33 1337 Sandvika , +47 (41452727) SITE RETG 08:00 13:00
Stop # Customer Start date/time End date/time
1 Joanna Jolanta Grochowska , Ovenbakken 16 Bu0102 1361 Østerås 08.05.2026 08:00:00 08.05.2026 17:00:00
 , 2124164745Sales order | 4106184116Freight Unit Number | +47 (91886979)Customer Phone No.
Stop # Customer Start date/time End date/time
3 Espen Sevendal , Løkebergkroken 12 1344 Haslum 08.05.2026 08:00:00 08.05.2026 17:00:00
 , 2123831828Sales order | 4106155580Freight Unit Number | +47 (97029756)Customer Phone No.
''';

      final customers = RoutePdfTextService.parseCustomers(raw);
      final espen = customers.where((c) => c.name.contains('Espen')).toList();
      expect(espen, isNotEmpty);
      expect(espen.first.freightUnit, '4106155580');
      expect(espen.first.salesOrder, '2123831828');
      expect(espen.first.salesOrder!.startsWith('2'), isTrue);
      expect(espen.first.freightUnit!.startsWith('4'), isTrue);
    });
  });
}
