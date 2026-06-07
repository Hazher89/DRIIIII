import 'package:driftpro/core/utils/business_days.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ferie over årsskifte 29.12.2025–02.01.2026', () {
    final start = DateTime(2025, 12, 29);
    final end = DateTime(2026, 1, 2);

    test('teller 4 virkedager totalt (1. jan er rød dag)', () {
      expect(BusinessDays.countInRange(start, end), 4);
    });

    test('fordeler 3 dager på 2025 og 1 dag på 2026', () {
      expect(BusinessDays.countInRangeForYear(start, end, 2025), 3);
      expect(BusinessDays.countInRangeForYear(start, end, 2026), 1);
      expect(BusinessDays.daysByYear(start, end), {2025: 3, 2026: 1});
    });
  });
}
