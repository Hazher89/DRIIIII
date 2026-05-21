import 'package:flutter_test/flutter_test.dart';
import 'package:driftpro/core/services/partner/route_pdf_text_service.dart';

void main() {
  test('parser Stowing Lane 17B fra Trip Overview', () {
    const text = '''
Trip Overview
Stowing Lane 17B
NO_O_M0089Resource ID
''';
    expect(RoutePdfTextService.parseStowingLane(text), '17B');
  });

  test('parser 1A og 1C som separate lanes', () {
    expect(RoutePdfTextService.normalizeStowingLane('1A'), '1A');
    expect(RoutePdfTextService.normalizeStowingLane('1C'), '1C');
  });

  test('composeRouteNotes inkluderer lane', () {
    final n = RoutePdfTextService.composeRouteNotes(
      stowingLane: '17B',
      userNote: 'Husk hub',
    );
    expect(n.contains('Stowing Lane: 17B'), true);
    expect(n.contains('Husk hub'), true);
  });
}
