import 'package:flutter_test/flutter_test.dart';
import 'package:driftpro/core/services/partner/delivery_postal_zones.dart';

void main() {
  group('DeliveryPostalZones', () {
    test('inclusive ranges and zones', () {
      expect(DeliveryPostalZones.deliversTo('0001'), isTrue);
      expect(DeliveryPostalZones.zoneFor('0001'), 1);
      expect(DeliveryPostalZones.zoneFor('2283'), 1);
      expect(DeliveryPostalZones.zoneFor('2284'), isNull);
      expect(DeliveryPostalZones.zoneFor('3015'), 1);
      expect(DeliveryPostalZones.zoneFor('3300'), 4);
      expect(DeliveryPostalZones.zoneFor('3525'), 1);
      expect(DeliveryPostalZones.zoneFor('3530'), 4);
      expect(DeliveryPostalZones.zoneFor('3601'), 1);
      expect(DeliveryPostalZones.zoneFor('3648'), 4);
      expect(DeliveryPostalZones.zoneFor('9990'), isNull);
    });

    test('answers yes/no for concrete postcodes', () {
      final yes = DeliveryPostalZones.tryAnswer(
        'Leverer dere til 3015?',
        audience: 'ccc',
      );
      expect(yes, isNotNull);
      expect(yes!.toLowerCase(), contains('ja'));
      expect(yes, contains('3015'));
      expect(yes, contains('sone 1'));

      final no = DeliveryPostalZones.tryAnswer(
        'Leverer vi til 9990?',
        audience: 'internal',
      );
      expect(no, isNotNull);
      expect(no!.toLowerCase(), contains('nei'));
    });

    test('overview without code', () {
      final text = DeliveryPostalZones.tryAnswer(
        'Hvilke postnummer leverer vi til?',
        audience: 'ccc',
      );
      expect(text, isNotNull);
      expect(text!, contains('0001'));
      expect(text, contains('2283'));
      expect(text, contains('sone'));
    });
  });
}
