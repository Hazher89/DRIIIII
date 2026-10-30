import 'package:flutter_test/flutter_test.dart';
import 'package:driftpro/core/services/partner/route_pdf_text_service.dart';

void main() {
  test('parseTotalDistanceKm reads Total distance KM', () {
    const raw =
        'Start date 30.10.26 Stowing Lane 2 Total distance 175.33 KM NO_O_M0020Resource ID';
    expect(RoutePdfTextService.parseTotalDistanceKm(raw), closeTo(175.33, 0.001));
  });

  test('parseTotalDistanceKm tolerates glued text', () {
    const raw = 'Totaldistance24.15KM NO_O_M0016';
    expect(RoutePdfTextService.parseTotalDistanceKm(raw), closeTo(24.15, 0.001));
  });

  test('parseConsumedWeightKg reads glued KGConsumed Weight', () {
    const raw = 'Driver Name 317.55 KGConsumed Weight Contact person';
    expect(RoutePdfTextService.parseConsumedWeightKg(raw), closeTo(317.55, 0.001));
  });
}
