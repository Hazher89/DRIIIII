import 'package:driftpro/core/utils/norwegian_national_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NorwegianNationalId.birthDateFrom', () {
    test('09020185446 → 9. februar 2001', () {
      final d = NorwegianNationalId.birthDateFrom('09020185446');
      expect(d, DateTime(2001, 2, 9));
    });

    test('individ 500–749 med yy < 54 → 2000-tallet', () {
      final d = NorwegianNationalId.birthDateFrom('01010150001');
      expect(d, DateTime(2001, 1, 1));
    });

    test('individ 500–749 med yy >= 54 → 1800-tallet', () {
      final d = NorwegianNationalId.birthDateFrom('01015450001');
      expect(d, DateTime(1854, 1, 1));
    });

    test('individ 000–499 → 1900-tallet', () {
      final d = NorwegianNationalId.birthDateFrom('01010149999');
      expect(d, DateTime(1901, 1, 1));
    });

    test('D-nummer med +40 på dag', () {
      final d = NorwegianNationalId.birthDateFrom('49020185446');
      expect(d, DateTime(2001, 2, 9));
    });
  });
}
